require 'pathname'                                                                #kütüphaneden çağırma varsa true döner
require 'pythonconfig'
require 'yaml'

CONFIG = Config.fetch('presentation', {})    

PRESENTATION_DIR = CONFIG.fetch('directory', 'p')                              		#klasörü açar
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')     		#2.parametredeki klasörü al
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')                         		#html dosyasını açar
IMAGE_GEOMETRY = [ 733, 550 ] 
DEPEND_KEYS    = %w(source css js)                                             		#w yazdırır ve atama yapılmış
DEPEND_ALWAYS  = %w(media)
TASKS = {       
    :index   => 'sunumları indeksle',                                          		#index dersek yandakini yazar
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation   = {}								
tag            = {}								

class File										#Sınıf oluştur
  @@absolute_path_here = Pathname.new(Pathname.pwd)					#Dosya yolunu ata			
  def self.to_herepath(path)								#self pointer olarak düşünülebilir
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?								#dosya yolu kontrol edilir
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :			#dosyaları listeler
      [path]
  end
end

def png_comment(file, string)
  require 'chunky_png'									#kütüphaneden çağırma varsa true döner
  require 'oily_png'						

  image = ChunkyPNG::Image.from_file(file)						#raked yorumunu yazar resim çağrıldığında
  image.metadata['Comment'] = 'raked'
  image.save(file)
end

def png_optim(file, threshold=40000)							#png resimleri kullan
  return if File.new(file).size < threshold						#threshold'u kırkbin'den küçükleri al döndür
  sh "pngnq -f -e .png-nq #{file}"						
  out = "#{file}-nq"									#çıkış
  if File.exist?(out)									#dosya kontrolü var mı yok mu diye 
    $?.success? ? File.rename(out, file) : File.delete(out)				#varsa adını file yap outu sil
  end
  png_comment(file, 'raked')								#raked yazar resim çağrıldığından
end

def jpg_optim(file)									#jpg resimleri kullandırır
  sh "jpegoptim -q -m80 #{file}"							#verilen değerlerle şekli düzenle 
  sh "mogrify -comment 'raked' #{file}"							#şeklin son halini tut					
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]			#png ve jpg için listeler

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }			#düzenlenen resimleri al
  end

  (pngs + jpgs).each do |f|								#png ve jpg için döngü
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }		#resimler aynı boyuttamı
    size, i = [w, h].each_with_index.max						#değilse yeniden düzenle
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) }   							#jpg boyutlarinı uygun hale getirilir
  jpgs.each { |f| jpg_optim(f) }							#png boyutlarinı uygun hale getirilir

  (pngs + jpgs).each do |f|								#png ve jpg için döngü							
    name = File.basename f								#adını değişkene ata
    FileList["*/*.md"].each do |src|							#.md dosyaları bul
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"					#ekrana yaz
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE)						#default bulunan config dosyaları

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)								#slayt dosyalarinin uzantıları
  chdir dir do
    name = File.basename(dir)                                                  			#aktif dizin yolunu görüntüler
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile		#var mı diye kontrol eder
    config = File.open(conffile, "r") do |f|#okumak için açılır dosya
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide										#lanslide false ise
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"					#hata mesajı
      exit 1											#çıkış
    end

    if landslide['destination']									#destination ayarinı kontol eder 
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"		#yoksa hata mesajı
      exit 1
    end

    if File.exists?('index.md')									#index.md var mı
      base = 'index'								
      ispublic = true										#dışardan kullanılır
    elsif File.exists?('presentation.md')							#presentation.md var mı
      base = 'presentation'
      ispublic = false										#dışardan kullanılmaz
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"		#hata mesajı
      exit 1											#çıkış
    end

    basename = base + '.html'#adı basename olan html uzantılı dosya ad.html li olur
    thumbnail = File.to_herepath(base + '.png')							#png uzantılı dosya 
    target = File.to_herepath(basename)								#html uzantılı dosya

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten 	#deps'e at
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)										#target'i sil 
    deps.delete(thumbnail)									#thumbnail'i sil

    tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v| 									#eksikleri tamamlamaya yarar
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]#çırpı 
	
presentation.each do |presentation, data|
  ns = namespace presentation do								#isimuzayı yarat
    file data[:target] => data[:deps] do |t|							#targeti aktar
      chdir presentation do									#sunum kısmı
        sh "landslide -i 									#{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do 							#resmi hedefe gonder
      next unless data[:public]									#gelenin erişilebilirliğini kontrol et
      sh "cutycapt " + 										#resimlerin boyutlarıyla oynar tamamı
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 									#{data[:thumbnail]}"
      png_optim(data[:thumbnail])
    end

    task :optim do										#optim görevi
      chdir presentation do									#aktif dizini değiştir
        optim
      end
    end

    task :index => data[:thumbnail]								#index görevini uygula

    task :build => [:optim, data[:target], :index]

    task :view do
      if File.exists?(data[:target])								#var mı yok mu kontrolü
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin" 				#yoksa hata mesajı
      end
    end

    task :run => [:build, :view]								#run görevini buil için uygula ve görüntüle

    task :clean do 
      rm_f data[:target] 									#clean görevini uygula
      rm_f data[:thumbnail]									#clean görevini uygula
    end

    task :default => :build 
  end

  ns.tasks.map(&:to_s).each do |t| 								#çırpı haritasında dolanma
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t 
  end
end

namespace :p do 										#isim uzayında görev belirler
  tasktab.each do |name, info| 
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do 										#görevi yap
    index = YAML.load_file(INDEX_FILE) || {}							#index file'ı yükle 
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|								#INDEX_FILE ı yazılabilir(w) aç
        f.write(index.to_yaml)									#yazma işlem
        f.write("---\n") 
      end
    end
  end

  desc "sunum menüsü"
  task :menu do
    lookup = Hash[										#çırpı tablosu
      *presentation.sort_by do |k, v| 								#k dan v'ye kadar sıralı kontrol
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }								#haritadan bul
      .flatten
    ]
    name = choose do |menu|  									#menüyü seç
      menu.default = "1"
      menu.prompt = color( 									#renk değişiklikleri sunumda
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end	
    directory = lookup[name]									#adı okuyup ata
    Rake::Task["#{directory}:run"].invoke							#klasöre görevi uygula
  end
  task :m => :menu
end

desc "sunum menüsü"										#başlık
task :p => ["p:menu"]
task :presentation => :p