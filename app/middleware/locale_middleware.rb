# frozen_string_literal: true

class LocaleMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    header_locale = Rack::Request.new(env).get_header('HTTP_X_LOCALE')
    return @app.call(env) unless header_locale

    I18n.with_locale(header_locale) do
      @app.call(env)
    end
  end
end
