class ApplicationController < ActionController::Base
  before_action :authorized
  helper_method :current_user
  helper_method :logged_in_admin?
  protect_from_forgery unless: -> { request.format.json? }

  def current_user
    User.find_by(id: session[:user_id])
  end

  def logged_in_admin?
    if not params[:bot_token].nil?
      return authorize_bot
    else
      return !current_user.nil?
    end
  end

  def authorized
    debug :"Authorizing..."
    if ENV['test_skip_authorized'].presence == 'true' and ENV["RAILS_ENV"] == 'test'
      debug :"Skipping authorized!!!"
      return
    elsif not params[:bot_token].nil?
      if authorize_bot
        debug :"Authorized bot."
      else
        debug :"Bot authorization failed."
      render inline: '', status: 403, encoding: 'application/json' and return
      end
    elsif logged_in_admin? and current_user.admin?
      debug :"Authorized user."
    else
      if request.fullpath == '/draft' # Okay I know this seems silly, but at some point, there will be additional pages for admins to access.
        session[:pre_login_request] = request.fullpath
        redirect_to login_url
      else
        not_found # Be sneaky about valid pages that need logins.
      end
    end
  end

  def authorize_bot
    params[:bot_token] == ENV['scraper_bot_token'] and Time.now < ENV['scraper_bot_timeout']
  end

  def not_found
    raise ActionController::RoutingError.new('Not Found')
  end

  def debug(symb, the_binding=nil)
    var_name = symb.to_s
    if the_binding
      var_value = eval(var_name, the_binding)
      logger.debug ">>>>>>> #{var_name}: #{var_value.inspect}"
    else
      logger.debug ">>>>>>> #{var_name}"
    end
  end

end
