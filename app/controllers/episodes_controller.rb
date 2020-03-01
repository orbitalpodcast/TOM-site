class EpisodesController < ApplicationController
  # allow not logged in users to access index and show.
  skip_before_action :authorized,         only: [:index, :show]
  # allow URL to reference slug or episode number. Create doesn't take an ID params, draft does its own work.
  before_action :set_episode,             only: [:show, :edit, :update, :destroy]

  # Multiple submit buttons do different things.
  before_action :handle_submit_and_override,    only: :update

  # GET /episodes
  # GET /episodes.json
  # GET /episodes.rss
  def index
    # Determine the appropriate range of episodes
    ep_range = []
    first_ep_num = Episode.published.first.number # Episode 1
    last_ep_num  = Episode.published.last.number  # Episode 250 or whatever
    unless params.has_key?(:begin) and params.has_key?(:end)
      # set ep_range if /episodes was called, or /to/ was malformed
      ep_range = [last_ep_num, last_ep_num - Settings.views.number_of_episodes_per_page + 1]
    else
      [params[:end], params[:begin]].each do |param|
        param = first_ep_num if param == 'first'
        param = last_ep_num  if param == 'last'
        ep_range << param
      end
    end
    ep_range.map! { |e| e.to_i} # sort can take strings or numbers, but they can't be mixed.
    ep_range.sort!

    # Pass selected episodes to views
    @episodes = Episode.published.where( number: (ep_range[0]..ep_range[1]) ).reverse
    @rss_episodes = Episode.published_with_audio.reverse # TODO build RSS tests. github.com/edgar/feedvalidator

    # Figure out what other ranges to link to, for pagination
    current_range_distance = ep_range[1] - ep_range[0]
    # move to higher number episodes (more recent)
    @previous_page_start = [ep_range[1] + 1 + current_range_distance, last_ep_num].min
    @previous_page_end   = @previous_page_start - current_range_distance
    @previous_page_start = nil if @previous_page_start == ep_range[1]
    # move to lower number episodes (older)
    @next_page_end   = [ep_range[0] - 1 - current_range_distance, first_ep_num].max
    @next_page_start = @next_page_end + current_range_distance
    @next_page_end = nil if @next_page_end == ep_range[0]

    respond_to do |format|
      format.html
      format.rss { render :layout => false }
    end
  end

  # GET /episodes/1
  # GET /episodes/1.json
  def show
  end

  # GET /episodes/new
  # def new
  # end

  # GET /episodes/1/edit
  def edit
  end

  # GET /draft
  def draft
    # Redirects to edit or acts as new
    if not Episode.draft_waiting?
      @episode = Episode.new
      @episode.number = (Episode.maximum('number') || 0) + 1
      # find next tuesday TODO: pull publish date/schedule out into config file
      @episode.publish_date = DateTime.parse('tuesday') + (DateTime.parse('tuesday') > DateTime.current ? 0:7)
      @episode.draft = true
      @episode.newsletter_status = 'not scheduled'
      render :new
    elsif Episode.not_published.count == 1
      @episode = Episode.not_published.last
      redirect_to edit_episode_path @episode
    else
      @episodes = Episode.not_published
      render :index
    end
  end

  # POST /episodes
  # POST /episodes.json
  def create
    @episode = Episode.new(episode_params.except(:images))
    @episode.slug = build_slug episode_title: episode_params[:title], episode_slug: episode_params[:slug]
    respond_to do |format|
      if @episode.save
        # We never publish episodes from create, so we want to redirect to edit, not to show.
        update_attachments
        format.html { redirect_to edit_episode_path(@episode), notice: 'Episode draft was successfully created.' }
        format.json { render :show, status: :created, location: @episode }
      else
        format.html { render :new }
        format.json { render json: {errors: @episode.errors}, status: 422, encoding: 'application/json' }
      end
    end
  end

  # PATCH/PUT /episodes/1
  # PATCH/PUT /episodes/1.json
  def update
    @episode.slug = build_slug episode_title: episode_params[:title], episode_slug: episode_params[:slug]
    respond_to do |format|
      if @episode.update( episode_params.merge!(slug:              @episode.slug,
                                                draft:             @episode.draft,
                                                newsletter_status: @episode.newsletter_status
                                                ).except(:images))
        # Did we fallback to a draft?
        # TODO: Make episode#update more friendly for published episodes.
        # Published episodes can get reverted to drafts if bad data is entered.
        if not errors_hash.nil?
          errors_hash.each do |att, err|
            @episode.errors.add att, err
          end
          flash.now[:notice] = 'Publish aborted. Episode draft was successfully updated.'
        else
          handle_newsletter
          update_attachments
          flash.now[:notice] = publish # returns a string, indicating if publish tasks were completed.
        end
        # TODO don't render new page without assuring episode.audio.analyzed? Perhaps force re-analysis before
        # publishing? Ditto image dimensions.
        format.html { render :edit }
        format.json { render :show, status: :accepted, location: @episode }
      else
        @episode.update_attribute(:newsletter_status, 'not scheduled') if @episode.newsletter_status == 'scheduling'
        @episode.reload # discards all user changes.
        # TODO Worth only resetting draft and newsletter_status in episode#update? If so, also add update_attachments.
        format.html { render :edit }
        format.json { render json: {errors: @episode.errors}, status: 422, encoding: 'application/json' }
      end
    end
  end   

  # PATCH/PUT /upload_image/1
  def upload_image
    unless @episode = Episode.find_by(number: params[:number])
      render inline: '{"errors":{"number":"non-existant episode number."}}', status: 422, encoding: 'application/json' and return
    end
    file = params[:file]
    if @episode.images.empty?
      position = 1
    else
      position = @episode.images.last.position + 1
    end
    @episode.images.create(position: position, caption: params[:caption]).image.attach(file)
  end

  # PATCH/PUT /upload_audio/1
  def upload_audio
    unless @episode = Episode.find_by(number: params[:number])
      render inline: '{"errors":{"number":"non-existant episode number."}}', status: 422, encoding: 'application/json' and return
    end
    file = params[:file]
    @episode.audio.attach(file)
  end

  # DELETE /episodes/1
  # DELETE /episodes/1.json
  def destroy
    @episode.destroy
    respond_to do |format|
      format.html { redirect_to episodes_url, notice: 'Episode was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

    def handle_submit_and_override
      # Before_action. Commit updates instance variable, override updates DB directly.
      # TODO: handle_submit_and_override currently updates draft whether or not publish encounters errors. Is this smart?
      # COMMIT
      case params[:commit]
      when 'Save as draft', 'Revert to draft'
        debug :"#{params[:commit]} clicked"
        @episode.draft = true
      when 'Draft and schedule newsletter'
        debug :"#{params[:commit]} clicked"
        @episode.draft = true
        @episode.newsletter_status = 'scheduling'
      when 'Cancel scheduled newsletter'
        debug :"#{params[:commit]} clicked"
        @episode.newsletter_status = 'canceling'
      when 'Publish', 'Publish changes'
        debug :"#{params[:commit]} clicked"
        @episode.draft = false
      else
        if request.format == 'application/json'
          debug :"Bot submission."
          @episode.draft = true
        else
          debug :"params[:commit]", binding
        end
      end
      # OVERRIDE
      case params[:override]
      when 'Skip newsletter'
        # Just update the following attributes, don't persist any changes coming in from the view, and ignore validations
        Episode.find_by(@episode.id).update(:newsletter_status, 'not sent')
      when 'Skip socials'
        Episode.find_by(@episode.id).update(ever_been_published: true,
                                            reddit_url: 'skipped',
                                            twitter_url: 'skipped')
      end
    end
    
    def handle_newsletter
      # Called on successful updates. Picks up where handle_submit_button leaves off. Called after successful save (so
      # that validations are run, and the emailer has good data), so we also modify the database with the new status.
      if @episode.newsletter_status == 'scheduling'
        schedule_newsletter
        @episode.update_attribute :newsletter_status, 'scheduled'
      elsif @episode.newsletter_status == 'canceling'
        unschedule_newsletter
        @episode.update_attribute :newsletter_status, 'not scheduled'
      end
    end

    def schedule_newsletter
      # TODO: detect and handle scheduling a newsletter when the time has already passed. Warn then send immediately?
      # TODO: change newsletter_job_id from a saved number to an activerecord association?
      email_time = DateTime.parse Settings.newsletter.default_send_time
      email_datetime = DateTime.new(@episode.publish_date.year, @episode.publish_date.month, @episode.publish_date.day,
                                    email_time.hour, email_time.min, email_time.sec, email_time.zone)
      logger.debug ">>>>>>> Scheduling newsletter for #{email_datetime}"

      scheduled_job = EpisodeMailer.delay(run_at: email_time).show_notes(@episode)
      @episode.update_attribute :newsletter_job_id, scheduled_job.id
    end

    def unschedule_newsletter
      logger.debug ">>>>>>> Deleting scheduled job #{@episode.newsletter_job_id}"
      Delayed::Job.find(@episode.newsletter_job_id).destroy!
    end

    def publish
      # Called on successful updates, and runs extra publication tasks if this isn't a draft.
      # Returns a string for the flash message.
      unless @episode.draft?
        unless @episode.ever_been_published?
          # Some things should not happen if an episode was pulled down after being published.
          debug :"Publishing socials and updating publish_date."
          # publish is called after validations were run, so we can safely update_attribute
          @episode.update_attribute :ever_been_published, true
          @episode.update_attribute :publish_date, Time.now
          post_to_twitter
          post_to_reddit 
        else
          debug :"Skipping socials."
        end
        return 'Episode was successfully published.'
      end
      'Episode draft was successfully updated.'
    end

    def post_to_twitter
      debug :"FAKE TWITTER: #{@episode.description} #{episode_url(@episode)}"
      # TWITTER_CLIENT.update "#{@episode.description} #{episode_url(@episode)}"
    end

    def post_to_reddit
      begin
        debug :'FAKE REDDIT'
        http_result = {'json'=> {'data'=> {'url'=> "http://www.reddit.com/r/orbitalpodcast/FAKE-URL/#{@episode.slug}"}}}
        # http_result = REDDIT_CLIENT.json(:post, '/api/submit',
        #                             DEFAULT_REDDIT_PARAMS.merge( {'title': @episode.full_title,
        #                                                           'url':   episode_url(@episode)} )
        #                                       )
      rescue RuntimeError => error
        debug :'REDDIT ERROR'
        debug :error, binding
        @episode.update_attribute :reddit_url, false
      else
        @episode.update_attribute :reddit_url, http_result['json']['data']['url']
      end
    end

    def set_episode
      @episode = Episode.find_by(slug: params[:id]) || Episode.find_by(number: params[:id])
      # TODO: set_episode results in two database calls when given a number. Worth checking params presence first?
      if @episode.draft?
        redirect_back(fallback_location: root_path, allow_other_host: false) unless logged_in_admin?
      end
    end

    def build_slug(episode_title:, episode_slug:)
      # Try and replace an empty slug or a placeholder.
      if episode_slug.empty? || episode_slug == 'untitled-draft'
        if episode_title.empty?
          return 'untitled-draft'
        else
          return Episode.slugify(episode_title)
        end
      end
      # If the slug isn't empty or a placeholder, no need to replace it.
      return episode_slug
    end

    def update_attachments
      # When saving an episode, a lot of things need to be done.
      create_images
      update_images
      delete_images
      delete_audio_attachment
    end

    def create_images
      # When images are uploaded, we need to create new Image objects, attach the files, and associate
      # the Image with this @episode
      for this_image in (episode_params[:images] || []) do
        if @episode.images.empty?
          position = 1
        else
          position = @episode.images.last.position + 1
        end
        @episode.images.create(position: position).image.attach(this_image)
      end
    end

    def update_images
      # When we save @episode, we also want to update the captions of the associated Images.
      positions = sort_image_positions image_params
      # Iterate over image_params and update each image in the database
      for image_id, image_deets in (image_params || {}) do
        unless image_to_be_deleted? image_id
          # Don't update images if they've been deleted.
          # TODO: handle validations fails in update_images
          Image.find_by(id: image_id).update(caption: image_deets[:caption], position: positions[image_id])
        end
      end
    end

    def image_to_be_deleted?(image_id)
      return false unless params[:remove_image]
      params[:remove_image].include? image_id
    end

    def sort_image_positions(incoming_params)
      # Take all the positions, sort, and make them consecutive.
      # Needs to be clever bc deletion takes place in the DB, but we have to honor user requests.
      # Takes a hash with string IDs and a deets hash: {'id' => {position: ##, caption:'caption'}}
      # Returns a hash with string IDs and int positions: {'##': #, '##': #}

      return if incoming_params.nil?
      # Create array of IDs and requested positions
      positions = incoming_params.transform_values { |deets| deets[:position] } || {}
      # Sort by requested position
      positions = positions.to_a.sort { |x,y| x[1]<=>y[1] }
      # Drop IDs that will be deleted
      positions.delete_if { |id, pos| image_to_be_deleted? id }
      # Re-number from 1
      positions.map!.with_index { |x,i| [x[0],i+1] }
      positions.to_h
    end

    def delete_images
     # When the user checks image deletion checkboxes, we need to go through and delete those Image objects.
      for image_id in (params[:remove_image] || []) do
        Image.find_by( id: image_id).destroy!
      end
    end

    def delete_audio_attachment
     # When the user checks the audio remove checkbox, we need to purge that attached file.
      if params.has_key? :remove_audio
        @episode.audio.purge
      end
    end

    def episode_params
      # Whitelist episode params
      params.require(:episode).permit(:commit, :number, :title, :slug, :publish_date, :description,
                                      :notes, :audio, :draft, :newsletter_status, :reddit_url, images: [])
    end
    def image_params(ids=nil)
      # Whitelist descriptions and positions, and merge. Returns {'id' => {position: ##, caption:'caption'}}
      # Only permits IDs of images already associated with @episode unless specified in arguments.
      if params[:image_captions] and params[:image_positions]
        ids ||= @episode.images.pluck(:id).map(&:to_s)
        positions = params.require(:image_positions).permit(ids).to_h
        captions  = params.require(:image_captions ).permit(ids).to_h
        captions.merge(positions) {|key,cap,pos| {position: pos.to_i, caption: cap}}
      end
    end

end
