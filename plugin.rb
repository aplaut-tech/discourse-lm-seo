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
    get '/categories/import' => 'categories_import#show'
    post '/categories/import' => 'categories_import#import'
    get '/categories/export' => 'categories_export#show'
    get '/categories/templates' => 'categories_seo_templates#show'
    put '/categories/templates' => 'categories_seo_templates#update'
  end



  ### Topics & Categories
  %w[category topic].each do |subject|
    subjects = subject.pluralize
    subjects_cap = subject.classify.pluralize
    subject_klass_name = subject.classify
    subject_klass = subject_klass_name.constantize

    subject_klass.register_custom_field_type('meta_title', :string)
    subject_klass.register_custom_field_type('meta_description', :string)
    subject_klass.register_custom_field_type('meta_keywords', :string)
    subject_klass.register_custom_field_type('seo_text', :string)

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


      class DiscourseSeo::#{subjects_cap}ImportController < ::ApplicationController
        def show
          render(nothing: true)
        end

        def import
          file = params.require(:file)
          importer = DiscourseSeo::#{subject_klass_name}Importer.new(file)
          importer.perform
          render(json: success_json.merge(success_count: importer.success_count,
            error_count: importer.error_count))
        end
      end


      class DiscourseSeo::#{subjects_cap}ExportController < ::ApplicationController
        def show
          render(nothing: true)
        end
      end
    RUBY
  end



  class DiscourseSeo::FileImporter
    attr_reader :success_count, :error_count

    def initialize(import_file)
      @import_file = import_file
      @success_count = 0
      @error_count = 0
    end

    def perform
      raise NotImplementedError
    end
  end

  class DiscourseSeo::TopicImporter < DiscourseSeo::FileImporter
    def perform
      @import_file.open
      CSV.parse(@import_file.read).each do |(id, _, title, seo_text, meta_title, meta_description, meta_keywords)|
        next if id == 'id' # Header row
        topic = Topic.find(id.to_i) rescue ((@error_count += 1); next)
        topic.title = title
        topic.custom_fields['seo_text'] = seo_text
        topic.custom_fields['meta_title'] = meta_title
        topic.custom_fields['meta_description'] = meta_description
        topic.custom_fields['meta_keywords'] = meta_keywords
        topic.save ? (@success_count += 1) : (@error_count += 1)
      end
      self
    ensure
      @import_file.close
    end
  end

  class DiscourseSeo::CategoryImporter < DiscourseSeo::FileImporter
    def perform
      @import_file.open
      CSV.parse(@import_file.read).each do |(id, _, name, seo_text, meta_title, meta_description, meta_keywords)|
        next if id == 'id' # Header row
        category = Category.find(id.to_i) rescue ((@error_count += 1); next)
        category.name = name
        category.custom_fields['seo_text'] = seo_text
        category.custom_fields['meta_title'] = meta_title
        category.custom_fields['meta_description'] = meta_description
        category.custom_fields['meta_keywords'] = meta_keywords
        category.save ? (@success_count += 1) : (@error_count += 1)
      end
      self
    ensure
      @import_file.close
    end
  end


  Jobs::ExportCsvFile.class_eval do
    self::HEADER_ATTRS_FOR[:topics_seo] = %w[
      id relative_url title seo_text meta_title meta_description meta_keywords
    ].freeze

    self::HEADER_ATTRS_FOR[:categories_seo] = %w[
      id relative_url name seo_text meta_title meta_description meta_keywords
    ].freeze

    def topics_seo_export
      return enum_for(:topics_seo_export) unless block_given?

      Topic.where(archetype: Archetype.default).each do |topic|
        yield get_topic_seo_fields(topic)
      end
    end

    def categories_seo_export
      return enum_for(:categories_seo_export) unless block_given?

      Category.all.each do |category|
        yield get_category_seo_fields(category)
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

    def get_category_seo_fields(c)
      cfs = c.custom_fields
      [
        c.id,
        c.url,
        c.name,
        cfs['seo_text'],
        cfs['meta_title'],
        cfs['meta_description'],
        cfs['meta_keywords']
      ]
    end
  end


  class DiscourseSeo::SeoFieldsRenderer
    # templates_type is topics or categories
    def initialize(object, params)
      object_type = object.class.name.underscore.pluralize
      @fields = object.custom_fields
      @templates = PluginStore.get('lm_seo', "#{object_type}_seo_templates") || {}
      @template_variables = prepare_template_variables(object, params).deep_stringify_keys
    end

    def field(name)
      @fields[name.to_s]
    end

    def field?(name)
      field(name).present?
    end

    def field_or_template(field_name)
      if field?(field_name)
        field(field_name)
      else
        template = @templates[field_name.to_s].presence || ''
        Liquid::Template.parse(template).render(@template_variables)
      end
    end

    private

    def prepare_template_variables(object, params)
      raise NotImplementedError
    end
  end

  class DiscourseSeo::TopicSeoFieldsRenderer < DiscourseSeo::SeoFieldsRenderer
    private def prepare_template_variables(topic, params)
      {
        topic: {
          title: topic.title
        },
        category: {
          name: topic.category.try(:name)
        },
        page: params[:page].try(:to_i) || 1
      }
    end
  end

  class DiscourseSeo::CategorySeoFieldsRenderer < DiscourseSeo::SeoFieldsRenderer
    private def prepare_template_variables(category, params)
      {
        category: {
          name: category.name
        },
        parent_category: {
          name: category.try(:parent_category).try(:name)
        },
        page: params[:page].try(:to_i) || 1
      }
    end
  end


  TopicView.prepend Module.new {
    def canonical_page? # TODO
      @page == 1 && [@username_filters, @filter, @post_number, @show_deleted].all?(&:blank?)
    end
  }


  # Meta keywords
  Deface::Override.new(
    virtual_path: 'layouts/application',
    name: 'seo-meta-keywords',
    insert_after: 'meta[name="description"]',
    text: <<-HTML
      <meta name="keywords" content="<%= @keywords_meta %>">
    HTML
  )

  # Topic breadcrumbs
  Deface::Override.new(
    virtual_path: 'topics/show',
    name: 'seo-topic-breadcrumbs',
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

  # Topic SEO text
  Deface::Override.new(
    virtual_path: 'topics/show',
    name: 'seo-topic-seo-text',
    insert_before: 'erb[silent]:contains("content_for :head do")',
    text: <<-HTML
      <% seo_fields_renderer = DiscourseSeo::TopicSeoFieldsRenderer.new(@topic_view.topic, params) %>
      <% if include_crawler_content? && @topic_view.canonical_page? && seo_fields_renderer.field?(:seo_text) %>
        <p class="topic-seo-text"><%= seo_fields_renderer.field(:seo_text) %></p>
      <% end %>
    HTML
  )

  # Category SEO text
  Deface::Override.new(
    virtual_path: 'list/list',
    name: 'seo-category-seo-text',
    insert_after: 'div[role="navigation"]',
    text: <<-HTML
      <% if @category && include_crawler_content? && (params[:page].blank? || params[:page].try(:to_i) == 1) %>
        <% seo_fields_renderer = DiscourseSeo::CategorySeoFieldsRenderer.new(@category, params) %>
        <% if seo_fields_renderer.field?(:seo_text) %>
          <p class="topic-seo-text"><%= seo_fields_renderer.field(:seo_text) %></p>
        <% end %>
      <% end %>
    HTML
  )

  # Remove anchor from topic title
  Deface::Override.new(
    virtual_path: 'topics/show',
    name: 'seo-topic-h1',
    replace_contents: 'h1',
    text: <<-HTML
      <%= Emoji.gsub_emoji_to_unicode(@topic_view.title) %>
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
