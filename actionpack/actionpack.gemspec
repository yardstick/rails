spec = Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = 'actionpack'
  s.version = '2.3.14'
  s.summary = "Web-flow and rendering framework putting the VC in MVC."
  s.description = %q{Eases web-request routing, handling, and response as a half-way front, half-way page controller. Implemented with specific emphasis on enabling easy unit/integration testing that doesn't require a browser.} #'

  s.author = "David Heinemeier Hansson"
  s.email = "david@loudthinking.com"
  s.rubyforge_project = "actionpack"
  s.homepage = "http://www.rubyonrails.org"

  s.requirements << 'none'

  s.add_dependency('activesupport', '= 2.3.14')
  s.add_dependency('rack', '~> 1.1.3')

  s.require_path = 'lib'
end
