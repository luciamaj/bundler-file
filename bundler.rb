#!/usr/bin/env ruby
Encoding.default_external = Encoding::UTF_8

require 'json'
require 'fileutils'

$dir = "#{File.dirname(File.realpath(__FILE__))}"

configDataPath = `#{$dir}/config/config.rb`
dataPathJson = JSON.parse(configDataPath)
$museo = dataPathJson["museo"]

@connettori = Dir["#{$dir}/connettori/#{$museo}/*"].map { |p| File.basename(p, File.extname(p)) }

jsonData = `#{$dir}/topics/#{$museo}/topics.rb`;
topicsJSON = JSON.parse(jsonData);
topicArray = topicsJSON["data"]["result"];
topics = [];
appsAPI = [];

for topic in topicArray do
    topics.push(topic.keys);
end   

topicArray.each { |t|
    t.values.each { |k|
        k.each { |el|
            appsAPI << el;
        }
    }
}

def isConnettore(connettore)
    @connettori.include?(connettore);
end

def versioni(topic)
    Dir.chdir("pacchetti/#{$museo}/#{topic}") do
        versioni = `git log master --pretty=format:"%h" | cut -d " " -f 1`.split("\n")
        return versioni
    end
end

def log(topic)
    Dir.chdir("pacchetti/#{$museo}/#{topic}") do
        log = `git log  -n 5 master --pretty=format:"%B"`
        
        return log
    end
end

def publish(connettore)
    jsonData = `#{$dir}/connettori/#{$museo}/#{connettore}.rb`;
    data = JSON.parse(jsonData);
    
    topic = data["topic"];
    type = data["type"];
    layout = connettore;
    dataString = <<-Q
let data = 
#{jsonData}
    Q

    # TODO: Spostare in def init(connettore)
    # crea la cartella pacchetti (se non esiste *)
    Dir.mkdir("pacchetti/#{$museo}") unless File.exists?("pacchetti/#{$museo}")
    # crea la cartella per i topic
    Dir.mkdir("pacchetti/#{$museo}/#{topic}") unless File.exists?("pacchetti/#{$museo}/#{topic}")
    # crea la cartella per l'app
    Dir.mkdir("pacchetti/#{$museo}/#{topic}/#{layout}") unless File.exists?("pacchetti/#{$museo}/#{topic}/#{layout}")
    # crea la cartella per il layout
    Dir.mkdir("pacchetti/#{$museo}/#{topic}/#{layout}/layout") unless File.exists?("pacchetti/#{$museo}/#{topic}/#{layout}/layout")
    # crea la cartella per gli assets
    Dir.mkdir("pacchetti/#{$museo}/#{topic}/#{layout}/layout/assets") unless File.exists?("pacchetti/#{$museo}/#{topic}/#{layout}/layout/assets")
    # crea la cartella per data
    Dir.mkdir("pacchetti/#{$museo}/#{topic}/#{layout}/data") unless File.exists?("pacchetti/#{$museo}/#{topic}/#{layout}/data")

    Dir.chdir("pacchetti/#{$museo}/#{topic}") do
        puts topic

        status = `git status 2>&1`
        if status.include? "ot a git repository"
            puts "Creando repo di git"
            `git init`
            puts ""
        end

        backToMaster = `git checkout master 2>&1`
        if backToMaster.include? "Switched"
            puts "Tornato all'ultimo commit, rilanciare per pubblicare le ultime modifiche"
            exit
        end
    end
    
    # qui si rompe per qualche motivo

    FileUtils.cp_r("layouts/#{$museo}/#{layout}/.", "pacchetti/#{$museo}/#{topic}/#{layout}/layout");

    File.write("pacchetti/#{$museo}/#{topic}/#{layout}/data/data.js", dataString);
    filesRegex = /\"([^\"]+\.(\w+)+)\"/
    #filesRegex = /\"([^\"]+\.[^\"]+)\"/
    files = jsonData.scan(filesRegex).map { |m| m[0] }

    puts "Asset da caricare #{files}"

    files.each { |f|
        configDataPath = `#{$dir}/config/config.rb`
        dataPathJson = JSON.parse(configDataPath)
        filesPath = dataPathJson["path_assets"]

        path = "#{filesPath}#{f}"
        # puts path;
        if File.file?(path)
            puts "\u2713 #{path}"
            FileUtils.ln_sf(File.realpath(path), "pacchetti/#{$museo}/#{topic}/#{layout}/layout/assets")
        else
            puts "\u2717 #{path}"
        end
    }
    puts ""

    filesInFolder = Dir["#{$dir}/pacchetti/#{$museo}/#{topic}/#{layout}/layout/assets/*"].map { |p| File.basename(p) }
    filesInFolder.each { |f| 
        path = "#{$dir}/pacchetti/#{$museo}/#{topic}/#{layout}/layout/assets/#{f}"
        if !files.include?(f) 
            # puts "Removing #{path}"
            FileUtils.rm(path)
        end
    }

    # MOVE CONFIG FILES IF ROKU
    if type == "player"
        FileUtils.cp_r("player-util/.", "pacchetti/#{$museo}/#{topic}");
    end

    if type == "pc"
        FileUtils.cp_r("pc-util/.", "pacchetti/#{$museo}/#{topic}");
    end

    # WRITE CACHE MANIFEST
    puts "sto scrivendo il manifest";

    Dir.chdir("pacchetti/#{$museo}/#{topic}") do
        files =  Dir.glob("**/*").select{ |e| File.file? e };
        manifest = File.new("manifest.mf", "w");
        manifest.puts("CACHE:")
        files.each { |f|
            # tolgo gli spazi
            manifest.puts(f.gsub(/\s/,'%20'));
        }
        manifest.close

        status = `git status 2>&1`

        if status.include? "working tree clean"
            puts "Niente di nuovo da pubblicare"
            exit
        end
        
        `git add -A .`
        `git commit -m "#{Time.now.strftime("%d/%m/%Y %H:%M:%S")}"`
        `git push`
    end
    # END CACHE MANIFEST
    
    puts "Ultimi 5 commit:"
    puts log(topic)
end

if ARGV.length == 0
    puts <<-Q
Comandi
#{$0} pubblica <connettore>
#{$0} versioni <topic>
#{$0} versione_corrente <topic>
#{$0} resetta <topic> <versione>
#{$0} topics
#{$0} connettori
    Q
elsif ARGV[0] == 'pubblica'
    connettore = ARGV[1]
    if !@connettori.include?(connettore)
        puts "#{$0} pubblica <connettore>"
        exit
    end

    publish(connettore)
elsif ARGV[0] == 'versione_corrente'
    topic = ARGV[1]
    if !topics.include?(topic)
        puts "Non trovo il topic '#{topic}'"
        puts "#{$0} versione_corrente <topic>"
        exit
    end

    Dir.chdir("pacchetti/#{$museo}/#{topic}") do
        versione = `git log -1 --pretty=format:"%h"`
        puts versione
    end


elsif ARGV[0] == 'resetta'
    topic = ARGV[1]
    if !topics.include?(topic)
        puts "Non trovo il topic '#{topic}'"
        puts "#{$0} resetta <topic> <versione>"
        exit
    end

    versione = ARGV[2]
    if !versione
        puts "#{$0} resetta <topic> <versione>"
        puts "Non trovo la versione '#{topic}'"
        puts ""
        puts "Versioni disponibili:"
        puts versioni(topic)
        exit
    end

    versioni = versioni(topic)
    selezionata = versioni.detect { |v| v.include?(versione) }
    if !selezionata
        puts "#{$0} resetta <topic> <versione>"
        puts "Non trovo la versione '#{versione}'"
        puts ""
        puts "Versioni disponibili:"
        puts versioni(topic)
        exit
    end
        
    puts "Resetto a #{selezionata}"
    Dir.chdir("pacchetti/#{$museo}/#{topic}") do
        `git checkout #{selezionata} 2>&1`
    end

elsif ARGV[0] == 'versioni'
    topic = ARGV[1]
    if !topics.include?(topic)
        puts "#{$0} versioni <topic>"
        exit
    end

    puts log(topic)
elsif ARGV[0] == 'topics'
    topics.each { |t| puts t }

elsif ARGV[0] == 'connettori'
    appsAPI.each { |c| 
        if isConnettore(c)
            puts c
        else 
            puts "il connettore" + c + "non esiste ancora"
        end
    }
end

exit
