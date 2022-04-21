module ApipieDoc
  module Api
    module V2
      module Projects
        extend ApipieDoc::Base
        resource ::Api::V2::ProjectsController

        doc_resource_description do
          formats %w(json)
          api_version 'v2'
          api_base_url '/api/v2'
          error :code => 404, :desc => "Not Found"
          error :code => 400, :desc => 'Bad request'
        end

        def_param_group :headers do
          header 'X-Locale', 'Localization header', required: false
          header 'X-AppVersion', 'App version header', required: false
          header 'X-AppName', 'App name header', required: false
        end

        def_param_group :app_code do
          param :code, String, :desc => 'NDA', :required => true
          param :type, %w(mobile web), :desc => "NDA"
          param :pin, String, :desc => 'NDA'
        end

        doc_for :show do
          api :GET, '/projects/show', 'Get project data'
          param_group :headers
          param_group :app_code
          error :code => 400, :desc => 'Invalid type or code'
          error :code => 403, :desc => "Forbidden (code is secret and pin doesn't match)"
        end

        doc_for :lookup do
          api :POST, '/projects/lookup', 'Get projects data for app codes array'
          description <<-EOS
            == Response
            Response will look something like <tt>NDA</tt>
            == Note
            If one of app codes is invalid, <tt>error</tt> key will be added instead of <tt>project</tt>
    
            For example, <tt>NDA</tt>
          EOS
          param_group :headers
          param :app_codes, Array, :of => Hash, :desc => 'Array of hashes of app codes', :required => true
          see "v1#projects#show", 'detailed params explanation'
          error :code => 400, :desc => 'No app codes'
          example 'NDA'
          example 'NDA'
        end

        doc_for :latest_versions do
          api :POST, '/projects/latest_versions', 'Get projects versions for app codes array'
          description <<-EOS
            == Response
            Response will look something like <tt>NDA</tt>
            == Note
            If one of app codes is invalid, <tt>error</tt> key will be added instead of <tt>project</tt>
    
            For example, <tt>NDA</tt>
          EOS
          param_group :headers
          param :app_codes, Array, :of => Hash, :desc => 'Array of hashes of app codes', :required => true
          see "v1#projects#show", 'detailed params explanation'
          error :code => 400, :desc => 'No app codes'
          example 'NDA'
          example 'NDA'
        end

        doc_for :auto_deploy_app_codes do
          api :GET, '/projects/auto_deploy_app_codes', 'Get app codes list for auto deployment'
          param_group :headers
          desc "Responds with list of app codes that are marked for auto deployment"
          example 'NDA'
        end
      end
    end
  end
end
