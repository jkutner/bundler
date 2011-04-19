# Bundler: a gem to bundle gems

Bundler is a tool that manages gem dependencies for your ruby application. It
takes a gem manifest file and is able to fetch, download, and install the gems
and all child dependencies specified in this manifest. It can manage any update
to the gem manifest file and update the bundle's gems accordingly. It also lets
you run any ruby code in context of the bundle's gem environment.

#### Information on this fork

The purpose of this Bundler fork is to add Maven support.  With this version of Bundler, you can include something like
this in your Gemfile:

    gem "commons-logging.commons-logging-api", "1.0.4", :mvn => {
            :artifact => "commons-logging-api",
            :group => "commons-logging",
            :version=>"1.0.4"}, :repo => "http://repo2.maven.org/maven2"

The API is clunky because I didn't want to mess with Bundler too much - so I was trying to fit the Maven stuff into
the existing constructs.  This will improve.  See this blog post for more information:

+  [http://jpkutner.blogspot.com/2011/04/bundler-and-maven-living-in-harmony.html](http://jpkutner.blogspot.com/2011/04/bundler-and-maven-living-in-harmony.html)

### Installation and usage

See [gembundler.com](http://gembundler.com) for up-to-date installation and usage instructions.

### Troubleshooting

For help with common problems, see [ISSUES](http://github.com/carlhuda/bundler/blob/master/ISSUES.md).

### Development

To see what has changed in recent versions of bundler, see the [CHANGELOG](http://github.com/carlhuda/bundler/blob/master/CHANGELOG.md).

The `master` branch contains our current progress towards version 1.1. Because of that, please submit bugfix pull requests against the `1-0-stable` branch.

### Upgrading from Bundler 0.8 to 0.9 and above

See [UPGRADING](http://github.com/carlhuda/bundler/blob/master/UPGRADING.md).

### Other questions

Feel free to chat with the Bundler core team (and many other users) on IRC in the  [#bundler](irc://irc.freenode.net/bundler) channel on Freenode, or via email on the [Bundler mailing list](http://groups.google.com/group/ruby-bundler).

