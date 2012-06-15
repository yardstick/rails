# Create compressed packages
spec = Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = 'actionmailer'
  s.summary = "Service layer for easy email delivery and testing."
  s.description = %q{Makes it trivial to test and deliver emails sent from a single service layer.}
  s.version = '2.3.14'

  s.author = "David Heinemeier Hansson"
  s.email = "david@loudthinking.com"
  s.rubyforge_project = "actionmailer"
  s.homepage = "http://www.rubyonrails.org"

  s.add_dependency('actionpack', '= 2.3.14')

  s.requirements << 'none'
  s.require_path = 'lib'
end
