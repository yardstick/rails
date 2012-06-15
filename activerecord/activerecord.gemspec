spec = Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = 'activerecord'
  s.version = '2.3.14'
  s.summary = "Implements the ActiveRecord pattern for ORM."
  s.description = %q{Implements the ActiveRecord pattern (Fowler, PoEAA) for ORM. It ties database tables and classes together for business objects, like Customer or Subscription, that can find, save, and destroy themselves without resorting to manual SQL.}

  s.add_dependency('activesupport', '= 2.3.14')

  s.require_path = 'lib'

  s.author = "David Heinemeier Hansson"
  s.email = "david@loudthinking.com"
  s.homepage = "http://www.rubyonrails.org"
  s.rubyforge_project = "activerecord"
end
