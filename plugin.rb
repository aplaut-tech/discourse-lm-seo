# name: lm-seo
# version: 0.0.1
# authors: Shoppilot team

gem 'polyglot', '0.3.5'
gem 'deface', '1.3.0', require_name: 'deface'
gem 'liquid', '4.0.0'

register_asset 'stylesheets/lm-seo.scss'


after_initialize do

  require_dependency 'application_controller'
  require_dependency 'admin_constraint'
  require_dependency 'jobs/regular/export_csv_file'
  require_dependency 'topic_view'
  require_dependency 'topics_helper'

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

    get '/topics' => 'topics#index'

    get '/topics/import' => 'topics_import#show'
    post '/topics/import' => 'topics_import#import'

    get '/topics/export' => 'topics_export#show'

    get '/topics/templates' => 'topics_seo_templates#show'
    put '/topics/templates' => 'topics_seo_templates#update'

    get '/categories' => 'categories#index'

    get '/categories/templates' => 'categories_seo_templates#show'
    put '/categories/templates' => 'categories_seo_templates#update'
  end



  ### Topics & Categories
  Topic.register_custom_field_type('meta_title', :string)
  Topic.register_custom_field_type('meta_description', :string)
  Topic.register_custom_field_type('meta_keywords', :string)
  Topic.register_custom_field_type('seo_text', :string)


  %w[category topic].each do |subject|
    subjects = subject.pluralize
    subjects_cap = subject.classify.pluralize

    class_eval <<-RUBY, __FILE__, __LINE__.next
      class DiscourseSeo::#{subjects_cap}Controller < ::ApplicationController
        def index
          render(nothing: true)
        end
      end

      class DiscourseSeo::#{subjects_cap}SeoTemplatesController < ::ApplicationController
        def show
          respond_to do |format|
            format.html { render(nothing: true) }
            format.json do
              templates = PluginStore.get('lm_seo', "#{subjects}_seo_templates") || {}
              render(json: success_json.merge(templates: templates))
            end
          end
        end

        def update
          templates = params.require(:templates).permit(:meta_title, :meta_description, :meta_keywords)
          PluginStore.set('lm_seo', "#{subjects}_seo_templates", templates)
          render(json: success_json)
        end
      end
    RUBY
  end


  class DiscourseSeo::TopicsImportController < ::ApplicationController
    def show
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


  class DiscourseSeo::TopicsExportController < ::ApplicationController
    def show
      render(nothing: true)
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
        topic.custom_fields['seo_text'] = seo_text
        topic.custom_fields['meta_title'] = meta_title
        topic.custom_fields['meta_description'] = meta_description
        topic.custom_fields['meta_keywords'] = meta_keywords
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


  class DiscourseSeo::MetaTemplatesRenderer
    # templates_type is topics or categories
    def initialize(templates_type)
      @templates = PluginStore.get('lm_seo', "#{templates_type}_seo_templates") || {}
    end

    def render(template_name, variables)
      template = @templates[template_name.to_s].presence || ''
      Liquid::Template.parse(template).render(variables.deep_stringify_keys)
    end
  end


  TopicView.prepend Module.new {
    def initialize(*)
      super
      @meta_templates_renderer = DiscourseSeo::MetaTemplatesRenderer.new(:topics)
    end

    def meta_title
      @_meta_title ||= @topic.custom_fields['meta_title'].presence ||
        render_default_meta_template(:meta_title)
    end

    def meta_description
      @_meta_description ||= @topic.custom_fields['meta_description'].presence ||
        render_default_meta_template(:meta_description)
    end

    def meta_keywords
      @_meta_keywords ||= @topic.custom_fields['meta_keywords'].presence ||
        render_default_meta_template(:meta_keywords)
    end

    def canonical_page?
      @page == 1 && [@username_filters, @filter, @post_number, @show_deleted].all?(&:blank?)
    end

    def seo_text
      @_seo_text ||= @topic.custom_fields['seo_text'].presence
    end

    def seo_text?
      !!seo_text
    end

    private

    def render_default_meta_template(template_name)
      @meta_templates_renderer.render(template_name, {
        topic: {
          title: @topic.title
        },
        category: {
          name: @topic.category.try(:name)
        },
        page: @page
      })
    end
  }


  # Seo text
  Deface::Override.new(
    virtual_path: 'topics/show',
    name: 'topics-show-seo-text',
    insert_before: 'erb[silent]:contains("content_for :head do")',
    text: <<-HTML
      <% if include_crawler_content? && @topic_view.canonical_page? && @topic_view.seo_text? %>
        <p class="topic-seo-text"><%= @topic_view.seo_text %></p>
      <% end %>
    HTML
  )

  # Non-anchor topic title
  Deface::Override.new(
    virtual_path: 'topics/show',
    name: 'topics-show-h1',
    replace_contents: 'h1',
    text: <<-HTML
      <%= Emoji.gsub_emoji_to_unicode(@topic_view.title) %>
    HTML
  )

  # Meta keywords
  Deface::Override.new(
    virtual_path: 'layouts/application',
    name: 'meta-keywords',
    insert_after: 'meta[name="description"]',
    text: <<-HTML
      <meta name="keywords" content="<%= @keywords_meta %>">
    HTML
  )

  # Topic breadcrumbs
  Deface::Override.new(
    virtual_path: 'topics/show',
    name: 'topics-show-breadcrumbs',
    replace: '#breadcrumbs',
    text: <<-HTML
      <div id="breadcrumbs" itemscope itemtype="http://schema.org/BreadcrumbList">
        <% @breadcrumbs.each_with_index do |bc, i| %>
          <div itemscope itemtype="http://schema.org/ListItem" itemprop="itemListElement">
            <a href="<%= bc[:url] %>" itemprop="item">
              <span itemprop="name"><%= bc[:name] %></span>
              <meta itemprop="position" content="<%= i + 1 %>" />
            </a>
          </div>
        <% end %>
      </div>
    HTML
  )


  Plugin::Filter.register(:topic_categories_breadcrumb) do |topic, breadcrumb|
    [{ url: '/', name: I18n.t('lm_seo.breadcrumbs.root') }, *breadcrumb]
  end



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
      respond_to do |format|
        format.html { render(nothing: true) }
        format.json do
          robots = PluginStore.get('lm_seo', 'robots')
          render(json: success_json.merge(robots: robots))
        end
      end
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
