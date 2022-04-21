class TrafficLogger
  API_URL_MATCHER = /(api\/|flow|\/export)/

  def initialize(app)
    @app = app
  end

  def call(env)
    app = API_URL_MATCHER.match(env['PATH_INFO']) ? Rack::ContentLength.new(@app) : @app

    app.call(env).tap do |(status, headers, response)|
      ::IncomingTrafficRecorder.new(status, headers, response, env).record
    end
  end
end
