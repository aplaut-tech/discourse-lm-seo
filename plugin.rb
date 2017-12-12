# name: lm-seo
# version: 0.0.1
# authors: Shoppilot team

register_asset 'stylesheets/lm-seo.scss'


after_initialize do

  require_dependency 'application_controller'
  require_dependency 'admin_constraint'

  module ::DiscourseSeo
    class Engine < ::Rails::Engine
      engine_name 'discourse_seo'
      isolate_namespace DiscourseSeo
    end
  end

  Discourse::Application.routes.append do
    namespace :admin, constraints: AdminConstraint.new do
      mount ::DiscourseSeo::Engine, at: '/seo'
    end
  end

  DiscourseSeo::Engine.routes.draw do
    get '/' => 'home#index'
    get '/robots' => 'robots#show'
    get '/sitemap' => 'sitemap#show'
  end

  class DiscourseSeo::HomeController < ::ApplicationController
    def index
      render(nothing: true)
    end
  end

  class DiscourseSeo::RobotsController < ::ApplicationController
    def show
      render(nothing: true)
    end
  end

  class DiscourseSeo::SitemapController < ::ApplicationController
    def show
      render(nothing: true)
    end
  end

end
