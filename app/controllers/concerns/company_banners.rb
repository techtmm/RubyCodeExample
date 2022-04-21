module ApipieDoc
  module Api
    module V2
      module CompanyBanners
        extend ApipieDoc::Base
        resource ::Api::V2::CompanyBannersController

        doc_resource_description do
          formats %w(json)
          api_version 'v2'
          api_base_url '/api/v2'
          error :code => 401, :desc => "Authentication Failure"
          error :code => 403, :desc => "The module is not available for your company"
          error :code => 404, :desc => "Not Found"
        end

        def_param_group :headers do
          header 'Authorization: Token token', 'Is a required authorization token', required: true
          header 'X-Locale', 'Localization header', required: false
        end

        def_param_group :company_banners_response do
          property '', Hash do
            property :image_file_name, String, desc: 'file name'
            property :image_content_type, String, desc: 'content type'
            property :image_file_size, Integer, desc: 'file size'
            property :image_url, String, desc: 'url'
            property :image_path, String, desc: 'path'
            property :updated_at, DateTime, desc: 'updated_at'
            property :tag, String, desc: 'tag'
            property :url, String, desc: 'url'
          end
        end

        doc_for :index do
          api :GET, '/company_banners', "Responds with company banners list"
          param_group :headers
          error :code => 401, :desc => "Authentication Failure"
          error :code => 403, :desc => "The module is not available for your company"
          error :code => 404, :desc => "Not Found"
          example 'NDA'
          returns desc: 'Company Banners response' do
            property :media_drive_files, Array, of: Hash do
              param_group :company_banners_response
            end
          end
        end

        doc_for :show do
          api :GET, '/company_banners/:id', "Responds with company banner image"
          param_group :headers
          param :id, /^[0-9]+$/, desc: "Company banner ID", required: true
          error :code => 401, :desc => "Authentication Failure"
          error :code => 403, :desc => "The module is not available for your company"
          error :code => 404, :desc => "Not Found"
          formats %w(jpg png)
        end
      end
    end
  end
end
