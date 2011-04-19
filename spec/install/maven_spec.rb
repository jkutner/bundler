require "spec_helper"

describe "bundle install with maven sources" do
  before :each do
    in_app_root
  end

  it "fetches gems" do
    gemfile <<-G
      gem "commons-logging.commons-logging-api", "1.0.4", :mvn => {:artifact => "commons-logging-api", :group => "commons-logging", :version=>"1.0.4"}, :repo => "http://repo2.maven.org/maven2"
    G

    # TODO make the entry look like this
#    gemfile <<-G
#      gem "commons-logging-api", "1.0.4", :mvn => "http://repo2.maven.org/maven2", :group_id => "commons-logging"
#    G

    bundle :install

    should_be_installed("commons-logging-api 1.0")
  end
end