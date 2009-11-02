#
#    this is usesthis.com, a sinatra application.
#    it is copyright (c) 2009 daniel bogan (d @ waferbaby, then a dot and a 'com')
#

require 'rubygems'
require 'sinatra'
require 'datamapper'
require 'haml'
require 'rdiscount'

Dir.glob('lib/*.rb') do |lib|
    require lib
end

configure do
    @config = YAML.load_file('usesthis.yml')
    DataMapper.setup(:default, @config[:database])
    
    set :admin_username, @config[:admin][:name]
    set :admin_password, @config[:admin][:password]
    set :haml, {:format => :html5}

    enable :sessions
end

helpers do
    def current_page
        @page = params[:page] && params[:page].match(/\d+/) ? params[:page].to_i : 1
    end
    
    def interview_url(interview)
        ENV['RACK_ENV'] == 'production' ? "http://#{interview.slug}.usesthis.com/" : "/#{interview.slug}/"
    end
    
    def needs_auth
        raise not_found unless has_auth?
    end
    
    def has_auth?
        session[:authorised] == true
    end
    
    def errors_for(object)
        result = "<ul class='errors'>\n"

        object.errors.each do |error|
            result += "<li>#{error}</li>\n";
        end
        
        result += "</ul>\n";
        
        result
    end
end

get '/' do
    @count, @interviews = Interview.paginated(:published_at.not => nil, :page => current_page, :per_page => 10, :order => [:published_at.desc])
    haml :index
end

get '/about/?' do
    haml :about
end

get '/feed/?' do
    content_type 'application/atom+xml', :charset => 'utf-8'

    @interviews = Interview.all(:published_at.not => nil, :order => [:published_at.desc])
    haml :feed, {:format => :xhtml, :layout => false}
end

get '/login/?' do
    @auth ||= Rack::Auth::Basic::Request.new(request.env)
    unless @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials[0] == options.admin_username && OpenSSL::Digest::SHA1.new(@auth.credentials[1]).hexdigest == options.admin_password
        response['WWW-Authenticate'] = %(Basic realm="The Setup")
        throw :halt, [401, "Don't think I don't love you."]
        return
    end
    
    session[:authorised] = true
    redirect '/'
end

get '/logout/?' do
    session[:authorised] = false
    redirect '/'
end

get '/interviews/new/?' do
    needs_auth
    
    @interview = Interview.new(:slug => params[:slug])
    haml :'interview.new', :layout => !request.xhr?
end

post '/interviews/new/?' do
    needs_auth
    
    @interview = Interview.new
    
    @interview.slug = params[:slug]
    @interview.person = params[:slug]
    @interview.summary = "(Summary)"
    @interview.credits = "(Credits)"
    @interview.contents = <<END
### Who are you and what do you do?

### What hardware do you use?

### And what software?

### What would be your dream setup?
END

    saved = @interview.save
    
    if request.xhr?
        unless saved
            status 400
            errors_for(@interview)
        end
    else
        saved ? redirect("/#{@interview.slug}/") : haml(:'interview.new')
    end
end

get '/wares/new/?' do
    needs_auth
    
    @ware = Ware.new(:slug => params[:slug])
    haml :'ware.new', :layout => !request.xhr?
end

post '/wares/new/?' do
    needs_auth

    @ware = Ware.new(params)
    saved = @ware.save
    
    if request.xhr?
        unless saved
            status 400
            errors_for(@ware)
        end
    else
        saved ? redirect('/') : haml(:'ware.new')
    end
end

get '/:slug/relink?' do |slug|
    needs_auth
    
    @interview = Interview.first(:slug => slug)
    raise not_found unless @interview
    
    @interview.link_to_wares
    @interview.save!
    
    RDiscount.new(@interview.contents_with_wares).to_html
end

get '/:slug/:key/?' do |slug, key|
    needs_auth
    
    @interview = Interview.first(:slug => slug)
    raise not_found unless @interview
    
    result = begin
        eval("@interview.#{key}")
    rescue
        nil
    end
    
    result
end

post '/:slug/:key/?' do |slug, key|
    needs_auth
    
    @interview = Interview.first(:slug => slug)
    raise not_found unless @interview
    
    @interview.update!(key => params[key]) unless params[key] == 'contents'
    
    case key
        when 'contents'
            @interview.contents = params[key]

            @interview.link_to_wares
            @interview.save!
            
            result = RDiscount.new(@interview.contents_with_wares).to_html
        when 'credits'
            result = RDiscount.new(@interview.credits).to_html
        when 'published_at'
            result = @interview.published_at.strftime("%b %d, %Y")
        else
            result = begin
                eval("@interview.#{key}")
            rescue
                nil
            end
        end

    result
end

get '/:slug/?' do
    @interview = Interview.first(:slug => params[:slug])
    raise not_found unless @interview

    haml :interview
end

not_found do
    haml :not_found, :layout => !request.xhr?
end

error do
    haml :error, :layout => !request.xhr?
end