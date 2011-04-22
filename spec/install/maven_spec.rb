require "spec_helper"

describe "bundle install with mvn" do
  it "fetches gems" do
    install_gemfile <<-G
      gem "mvn:org.slf4j:slf4j-simple", "1.6.1", :mvn => 'http://repo1.maven.org/maven2/'
    G

    should_be_installed("mvn:org.slf4j:slf4j-simple 1.6.1")
  end

  it "fetches gems" do
    install_gemfile <<-G
      gem "mvn:org.slf4j:slf4j-simple", "1.6.1"
    G

    should_be_installed("mvn:org.slf4j:slf4j-simple 1.6.1")
  end

  it "fetches gems" do
    install_gemfile <<-G
      mvn 'http://repo1.maven.org/maven2/' do
        gem "mvn:org.slf4j:slf4j-simple", "1.6.1"
      end
    G

    should_be_installed("mvn:org.slf4j:slf4j-simple 1.6.1")
  end
end