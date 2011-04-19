require "uri"
require 'rubygems/user_interaction'
require "rubygems/installer"
require "rubygems/spec_fetcher"
require "rubygems/format"
require "digest/sha1"
require "open3"
require "ostruct"
require 'net/http'
require 'fileutils'
require 'yaml'
require 'rexml/document'
require 'rexml/xpath'

module Bundler
  module Source

    class Maven 
      attr_reader :pom
    
      DEFAULT_GLOB = "{,*/}*.gemspec"
      
      def initialize(options)
        # TODO ensure that maven is installed
      
        @options = options
        @glob = options["glob"] || DEFAULT_GLOB        

        @allow_cached = false
        @allow_remote = false
               
        @name = options["name"]
        
        if options["pom"]
          @pom_url = options["pom"]
          raise "Bundler doesn't know how to parse a pom file yet"
          #@artifact = MavenHelper.parse_pom
        else
          @artifact = options["artifact"]
          @repo = options["repo"]
            
          #@pom_url = PomSpec.to_maven_url @artifact[:group], @artifact[:artifact], @artifact[:version], @repo 
        end
      end 
      
      def remote!
        @allow_remote = true
      end

      def cached!
        @allow_cached = true
      end
      
      def self.from_lock(options)
        # for now 'mvn' option is the pom
        new(options.merge("artifact" => {
            :group => options.delete("group_id"),
            :artifact => options.delete("artifact_id"),
            :version => options.delete("version")},
            :repo => options.delete("remote")))
      end

      def to_lock
        out = "MAVEN\n"
        out << "  group_id: #{@artifact['group']}\n"
        out << "  artifact_id: #{@artifact['artifact']}\n"
        out << "  version: #{@artifact['version']}\n"
        out << "  remote: #{@repo}\n"
        out << "  glob: #{@glob}\n" unless @glob == DEFAULT_GLOB
        out << "  specs:\n"
      end
      
      def install(spec)
        path = PomSpec.create_gem(spec, @pom)

        # TODO prevent reinstalling it
#        if installed_specs[spec].any?
#          Bundler.ui.info "Using #{spec.name} (#{spec.version}) "
#          return
#        end

        Bundler.ui.info "Installing #{spec.name} (#{spec.version}) "

        install_path = Bundler.requires_sudo? ? Bundler.tmp : Gem.dir
        options = { :install_dir         => install_path,
                    :ignore_dependencies => true,
                    :wrappers            => true,
                    :env_shebang         => true }
        options.merge!(:bin_dir => "#{install_path}/bin") unless spec.executables.nil? || spec.executables.empty?

        installer = Gem::Installer.new path, options
        installer.install

        # SUDO HAX
        if Bundler.requires_sudo?
          sudo "mkdir -p #{Gem.dir}/gems #{Gem.dir}/specifications"
          sudo "cp -R #{Bundler.tmp}/gems/#{spec.full_name} #{Gem.dir}/gems/"
          sudo "cp -R #{Bundler.tmp}/specifications/#{spec.full_name}.gemspec #{Gem.dir}/specifications/"
          spec.executables.each do |exe|
            sudo "mkdir -p #{Gem.bindir}"
            sudo "cp -R #{Bundler.tmp}/bin/#{exe} #{Gem.bindir}"
          end
        end

        spec.loaded_from = "#{Gem.dir}/specifications/#{spec.full_name}.gemspec"
      end

      def load_specs
        # todo cache pom so we don't always have to download it
        location = PomSpec.to_maven_url(@artifact[:group], @artifact[:artifact], @artifact[:version], @repo)
        idx = Index.new 
        spec, @pom = PomSpec.build(location, @repo)
        spec.source = self
        spec.loaded_from = "#{Gem.dir}/specifications/#{spec.full_name}.gemspec"
        idx << spec
        idx
      end

      def specs
        @specs ||= load_specs
      end

      private
              
        def sudo(str)
          Bundler.sudo(str)
        end
    end
    
  class PomFetcher

    def self.fetch(path, options = {})
      puts "Reading POM from #{path}" if options[:verbose]

      fetch_pom(path, options)
    end

    def self.clean_pom(pom) #avoid namespaces errors and gotchas
      pom.gsub(/<project[^>]+/, '<project>')
    end

    def self.fetch_pom(path, options = {})
      path =~ /^http:\/\// ? fetch_from_url(path, options) :
        fetch_from_file(path, options)
    end

    private
    def self.fetch_from_url(path, options = {})
      Net::HTTP.get(URI.parse(path))
    end

    def self.fetch_from_file(path, options = {})
      File.read(path)
    end
  end
  
  
  module XmlUtils
    def xpath_text(element, node)
      first = REXML::XPath.first(element, node) and first.text
    end

    def xpath_dependencies(element)
      deps = REXML::XPath.first(element, '/project/dependencies')
      pom_dependencies = []

      if deps
        deps.elements.each do |dep|
          next if xpath_text(dep, 'optional') == 'true'

          dep_group = xpath_text(dep, 'groupId')
          dep_artifact = xpath_text(dep, 'artifactId')
          dep_version = xpath_text(dep, 'version')
          dep_scope = xpath_text(dep, 'scope')

          if !['test', 'provided'].include?(dep_scope)
            # TODO: Parse maven version number modifiers, i.e: [1.5,)
            pom_dependencies << if dep_version
              Gem::Dependency.new(maven_to_gem_name(dep_group, dep_artifact),
                "=#{maven_to_gem_version(dep_version)}")
            else
              Gem::Dependency.new(maven_to_gem_name(dep_group, dep_artifact))
            end
          end
        end
      end

      pom_dependencies
    end

    def xpath_authors(element)
      developers = REXML::XPath.first(element, 'project/developers')

      authors = if developers
        developers.elements.map do |el|
          xpath_text(el, 'name')
        end
      end || []
    end

    def xpath_group(element)
      xpath_text(element, '/project/groupId') || xpath_text(element, '/project/parent/groupId')
    end

    def xpath_parent_group(element)
      parent = REXML::XPath.first(element, 'parent')
      parent ? xpath_group(parent) : nil
    end

    def xpath_parent_artifact(element)
      parent = REXML::XPath.first(element, 'parent')
      parent ? xpath_text(element, 'parent/artifactId') : nil
    end

    def xpath_parent_version(element)
      parent = REXML::XPath.first(element, 'parent')
      parent ? xpath_text(element, 'parent/version') : nil
    end

    def xpath_properties(element)
      props = REXML::XPath.first(element, '/project/properties')
      pom_properties = {}

      if props
        props.elements.each do |prop|
          pom_properties[prop.name] = prop.text
        end
      end

      pom_properties
    end
  end
  
  class PomSpec
    extend XmlUtils

    @@properties = {}

    def self.build(location, maven_base_url, properties={})
      @@properties.merge!(properties)
      pom_doc = PomFetcher.fetch(location)
      pom = PomSpec.parse_pom(pom_doc, maven_base_url)
      spec = PomSpec.generate_spec(pom)
      return spec, pom
    end
   
    def self.maven_to_gem_version(maven_version)
      maven_version = parse_property(maven_version)
      maven_version = maven_version.gsub(/alpha/, '0')
      maven_version = maven_version.gsub(/beta/, '1')
      maven_numbers = maven_version.gsub(/\D+/, '.').split('.').find_all { |i| i.length > 0 }
      if maven_numbers.empty?
        '0.0.0'
      else
        maven_numbers.join('.')
      end
    end

    def self.is_property?(s)
      !(s.match(/\A\$\{/).nil?)
    end

    def self.parse_property(property)
      if is_property?(property)
        property_name = property.gsub(/\A\$\{/, '').gsub(/\}\z/, '')
        property = @@properties[property_name]
        raise "No value found for property: ${#{property_name}}" if property.nil?
      end
      property
    end

    def self.parse_pom(pom_doc, maven_base_url, options = {})
      puts "Processing POM" if options[:verbose]

      pom = OpenStruct.new
      document = REXML::Document.new(pom_doc, maven_base_url)

#      pom.parent = OpenStruct.new
      pom.parent_group = xpath_parent_group(document)
      pom.parent_artifact = xpath_parent_artifact(document)
      pom.parent_version = xpath_parent_version(document)

      if pom.parent_version
        parent_pom_path = to_maven_path(pom.parent_group, pom.parent_artifact, pom.parent_version)
        parent_pom_location ="#{maven_base_url}/#{parent_pom_path}"
        parent_pom_doc = PomFetcher.fetch(parent_pom_location)
        pom.parent = parse_pom(parent_pom_doc, maven_base_url)

        @@properties['parent.version'] = pom.parent_version
      end

      pom.group = xpath_group(document)
      pom.artifact = xpath_text(document, '/project/artifactId')
      pom.maven_version = parse_property(xpath_text(document, '/project/version') || xpath_text(document, '/project/parent/version'))
      pom.version = maven_to_gem_version(pom.maven_version)

      @@properties.merge! xpath_properties(document)
      @@properties['project.groupId'] = pom.group
      @@properties['project.artifactId'] = pom.artifact
      @@properties['project.version'] = pom.maven_version

      pom.description = xpath_text(document, '/project/description')
      pom.url = xpath_text(document, '/project/url')
      pom.dependencies = xpath_dependencies(document)
      pom.authors = xpath_authors(document)

      pom.name = maven_to_gem_name(pom.group, pom.artifact)
      pom.lib_name = "#{pom.artifact}.rb"
      pom.gem_name = "#{pom.name}-#{pom.version}"
      pom.jar_file = "#{pom.artifact}-#{pom.maven_version}.jar"
      pom.remote_dir = to_maven_path(pom.group, pom.artifact, pom.maven_version)
      pom.remote_jar_url = "#{maven_base_url}/#{pom.remote_dir}/#{pom.jar_file}"
      pom.gem_file = "#{pom.gem_name}-java.gem"
      pom
    end

    def self.generate_spec(pom, options = {})
      spec = Gem::Specification.new do |specification|
        specification.platform = "ruby"
        specification.version = pom.version
        specification.name = pom.name
        pom.dependencies.each {|dep| specification.dependencies << dep}
        specification.authors = pom.authors
        specification.description = pom.description
        specification.homepage = pom.url
        specification.files = ["lib/#{pom.lib_name}", "lib/#{pom.jar_file}"]
      end
    end

    def self.create_gem(spec, pom, options = {})
      gem = create_files(spec, pom, options)
    end

    def self.to_maven_url(group, artifact, version, maven_base_url)
      "#{maven_base_url}/#{self.to_maven_pom(group, artifact, version)}"
    end

    private

    def self.to_maven_path(group, artifact, version)
      "#{group.gsub('.', '/')}/#{artifact}/#{version}"
    end

    def self.to_maven_pom(group, artifact, version)
      "#{to_maven_path(group, artifact, version)}/#{artifact}-#{version}.pom"
    end

    def self.maven_to_gem_name(group, artifact, options = {})
      "#{parse_property(group)}.#{parse_property(artifact)}"
    end

    def self.create_files(specification, pom, options = {})
      gem_dir = create_tmp_directories(pom, options)

      ruby_file_contents(gem_dir, pom, options)
      jar_file_contents(gem_dir, pom, options)
      metadata_contents(gem_dir, specification, pom, options)
      gem_contents(gem_dir, pom, options)
    ensure
      FileUtils.rm_r(gem_dir) if gem_dir
    end

    def self.create_tmp_directories(pom, options = {})
      gem_dir = "/tmp/#{pom.name}.#{$$}"
      puts "Using #{gem_dir} work dir" if options[:verbose]
      unless File.exist?(gem_dir)
        FileUtils.mkdir_p(gem_dir)
        FileUtils.mkdir_p("#{gem_dir}/lib")
      end
      gem_dir
    end

    def self.ruby_file_contents(gem_dir, pom, options = {})
      titleized_classname = pom.artifact.split('-').collect { |e| e.capitalize }.join
      ruby_file_content = <<HEREDOC
module #{titleized_classname}
  VERSION = '#{pom.version}'
  MAVEN_VERSION = '#{pom.maven_version}'
end
begin
  require 'java'
  require File.dirname(__FILE__) + '/#{pom.jar_file}'
rescue LoadError
  puts 'JAR-based gems require JRuby to load. Please visit www.jruby.org.'
  raise
end
HEREDOC

      ruby_file = "#{gem_dir}/lib/#{pom.lib_name}"
      puts "Writing #{ruby_file}" if options[:verbose]
      File.open(ruby_file, 'w') do |file|
        file.write(ruby_file_content)
      end
    end

    def self.jar_file_contents(gem_dir, pom, options = {})
      puts "Fetching #{pom.remote_jar_url}" if options[:verbose]
      uri = URI.parse(pom.remote_jar_url)
      jar_contents = Net::HTTP.get(uri)
      File.open("#{gem_dir}/lib/#{pom.jar_file}", 'w') {|f| f.write(jar_contents)}
    end

    def self.metadata_contents(gem_dir, spec, pom, options = {})
      metadata_file = "#{gem_dir}/metadata"
      puts "Writing #{metadata_file}" if options[:verbose]
      File.open(metadata_file, 'w') do |file|
        file.write(spec.to_yaml)
      end
    end

    def self.gem_contents(gem_dir, pom, options = {})
      puts "Building #{pom.gem_file}" if options[:verbose]
      Dir.chdir(gem_dir) do
        fail unless
          system('gzip metadata') and
          system('tar czf data.tar.gz lib/*') and
          system("tar cf ../#{pom.gem_file} data.tar.gz metadata.gz")
      end

      File.expand_path("../#{pom.gem_file}", gem_dir) # return the gem file
    end
  end
  
  end
end
