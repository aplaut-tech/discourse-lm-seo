# name: lm-seo
# version: 0.0.1
# authors: Shoppilot team

gem 'polyglot', '0.3.5'
gem 'deface', '1.3.0', require_name: 'deface'

register_asset 'stylesheets/lm-seo.scss'


after_initialize do

  require_dependency 'application_controller'
  require_dependency 'admin_constraint'
  require_dependency 'jobs/regular/export_csv_file'
  require_dependency 'topic_view'

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
    put '/robots' => 'robots#update'
    get '/sitemap' => 'sitemap#show'
    get '/topics' => 'topics#index'
    post '/topics' => 'topics#import'
  end



  ### Topics
  Topic.register_custom_field_type('meta_title', :string)
  Topic.register_custom_field_type('meta_description', :string)
  Topic.register_custom_field_type('meta_keywords', :string)
  Topic.register_custom_field_type('seo_text', :string)


  class DiscourseSeo::TopicsController < ::ApplicationController
    def index
      render(nothing: true)
    end

    def import
      file = params.require(:file)
      importer = DiscourseSeo::TopicImporter.new(file)
      importer.perform
      render(json: success_json.merge(success_count: importer.success_count,
        error_count: importer.error_count))
    end
  end


  class DiscourseSeo::TopicImporter
    attr_reader :success_count, :error_count

    def initialize(import_file)
      @import_file = import_file.tap(&:open)
      @success_count = 0
      @error_count = 0
    end

    def perform
      CSV.parse(@import_file.read).each do |(id, _, title, seo_text, meta_title, meta_description, meta_keywords)|
        topic = Topic.find(id.to_i) rescue next
        topic.title = title
        topic.custom_fields['seo_text'] = seo_text || ''
        topic.custom_fields['meta_title'] = meta_title || ''
        topic.custom_fields['meta_description'] = meta_description || ''
        topic.custom_fields['meta_keywords'] = meta_keywords || ''
        topic.save ? (@success_count += 1) : (@error_count += 1)
      end
    ensure
      @import_file.close
    end
    self
  end


  Jobs::ExportCsvFile.class_eval do
    self::HEADER_ATTRS_FOR[:topics_seo] = %w[
      id relative_url title seo_text meta_title meta_description meta_keywords
    ].freeze

    def topics_seo_export
      return enum_for(:topics_seo_export) unless block_given?

      Topic.where(archetype: Archetype.default).each do |topic|
        yield get_topic_seo_fields(topic)
      end
    end

    private

    def get_topic_seo_fields(t)
      cfs = t.custom_fields
      [
        t.id,
        t.relative_url,
        t.title,
        cfs['seo_text'],
        cfs['meta_title'],
        cfs['meta_description'],
        cfs['meta_keywords']
      ]
    end
  end


  TopicView.class_eval do
    def seo_page?
      @page == 1 && [@username_filters, @filter, @post_number, @show_deleted].all?(&:blank?)
    end

    def seo_text
      @_seo_text ||= @topic.custom_fields['seo_text'].presence
    end

    def seo_text?
      !!seo_text
    end
  end


  Deface::Override.new(
    virtual_path: 'topics/show',
    name: 'topics-show-seo-text',
    insert_before: 'erb[silent]:contains("content_for :head do")',
    text: <<-ERB
      <% if include_crawler_content? && @topic_view.seo_page? && @topic_view.seo_text? %>
        <p class="topic-seo-text"><%= @topic_view.seo_text %></p>
      <% end %>
    ERB
  )



  ### Home ###
  class DiscourseSeo::HomeController < ::ApplicationController
    def index
      render(nothing: true)
    end
  end



  ### Robots ###
  RobotsTxtController.class_eval do
    def index
      robots = PluginStore.get('lm_seo', 'robots')
      render(text: robots, content_type: 'text/plain')
    end
  end


  class DiscourseSeo::RobotsController < ::ApplicationController
    def show
      robots = PluginStore.get('lm_seo', 'robots')
      render(json: success_json.merge(robots: robots))
    end

    def update
      robots = params[:robots]
      PluginStore.set('lm_seo', 'robots', robots)
      render(json: success_json)
    end
  end



  ### Sitemap ###
  class DiscourseSeo::SitemapController < ::ApplicationController
    def show
      render(nothing: true)
    end
  end

end
