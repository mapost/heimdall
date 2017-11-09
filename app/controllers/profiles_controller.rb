class ProfilesController < ApplicationController
  before_action :set_profile, only: [:show, :edit, :update, :destroy, :vis, :nist_800_53]

  @@nist_800_53_json = nil

  # GET /profiles
  # GET /profiles.json
  def index
    @profiles = Profile.all
  end

  # GET /profiles/1
  # GET /profiles/1.json
  def show
    @depend = @profile.depends.new()
    @support = @profile.supports.new()
  end

  # GET /profiles/new
  def new
    @profile = Profile.new
  end

  # GET /profiles/1/edit
  def edit
  end

  # POST /profiles
  # POST /profiles.json
  def create
    @profile = Profile.new(profile_params)

    respond_to do |format|
      if @profile.save
        format.html { redirect_to @profile, notice: 'Profile was successfully created.' }
        format.json { render :show, status: :created, location: @profile }
      else
        format.html { render :new }
        format.json { render json: @profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /profiles/1
  # PATCH/PUT /profiles/1.json
  def update
    respond_to do |format|
      if @profile.update(profile_params)
        format.html { redirect_to @profile, notice: 'Profile was successfully updated.' }
        format.json { render :show, status: :ok, location: @profile }
      else
        format.html { render :edit }
        format.json { render json: @profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /profiles/1
  # DELETE /profiles/1.json
  def destroy
    @profile.destroy
    respond_to do |format|
      format.html { redirect_to profiles_url, notice: 'Profile was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def vis
  end

  def vis2
    @profile = Profile.find(params[:id])
    @profile.controls.each do |control|
      control.tags.where(:name => 'nist').each do |tag|
        logger.debug "#{control.control_id}: #{tag.value}"
      end
    end
  end

  def nist_800_53
    category = nil
    category = params[:category] if params.has_key?(:category)
    unless @@nist_800_53_json
      file = File.read("#{Rails.root}/data/nist_800_53.json")
      @@nist_800_53_json = JSON.parse(file)
    end
    nist_hash = @profile.nist_hash category
    logger.debug "nist_hash: #{nist_hash.inspect}"
    new_hash = @@nist_800_53_json.deep_dup
    total_impact = 0
    total_children = 0
    new_hash["children"].each do |cf|
      cf_total_impact = 0.0
      cf_total_children = 0
      cf["children"].each do |control|
        control_total_impact = 0.0
        control_total_children = 0
        if nist_hash[control["name"]]
          control.delete('value')
          control["children"] = nist_hash[control["name"]]
          control["children"].each do |child|
            logger.debug "CHILD #{child.inspect}"
            if child[:impact]
              control_total_children += 1
              control_total_impact += child[:impact]
            end
            logger.debug "#{control['name']}: #{child['impact']}, cont_impact: #{control_total_impact}, cont_children: #{control_total_children}"
          end
        end
        logger.debug "SET #{control['name']} impact: #{control_total_impact == 0.0 ? 0.0 : control_total_impact/control_total_children}"
        control["impact"] = control_total_impact == 0.0 ? 0.0 : control_total_impact/control_total_children
        cf_total_impact += control_total_impact
        cf_total_children += control_total_children
        logger.debug "#{cf['name']} cft_impact: #{cf_total_impact}, cft_children: #{cf_total_children}"
      end
      logger.debug "SET #{cf['name']} impact: #{cf_total_impact == 0.0 ? 0.0 : cf_total_impact/cf_total_children}"
      cf["impact"] = cf_total_impact == 0.0 ? 0.0 : cf_total_impact/cf_total_children
      total_impact += cf_total_impact
      total_children += cf_total_children
    end
    new_hash["impact"] = total_impact == 0.0 ? 0.0 : total_impact/total_children
    logger.debug "new_hash: #{new_hash.inspect}"
    render json: new_hash
  end

  def upload
    file = params[:file]
    @profile = Profile.create(transform(JSON.parse(file.read)))
    redirect_to @profile
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_profile
      @profile = Profile.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def profile_params
      params.require(:profile).permit(:id, :name, :title, :maintainer, :copyright, :copyright_email, :license, :summary, :version, :sha256, :depends, :supports, :controls, :groups, :profile_attributes)
    end

    #convert parameters with hyphen to parameters with underscore and rename 'attributes'
    def transform hash
      #logger.debug("OLD HASH: #{hash.inspect}")
      hash["controls"].each do |control|
        tags = control.delete('tags')
        new_tags = []
        logger.debug("TAGS: #{tags.inspect}")
        tags.each do |key, value|
          new_tags << {"name": "#{key}", "value": value}
        end
        logger.debug("new tags: #{new_tags.inspect}")
        control["tags"] = new_tags
        source_location = control.delete('source_location')
        source_location.each do |key, value|
          control["sl_#{key}"] = value
        end
      end
      hash['attributes'].each do |attr|
        options = attr.delete('options')
        options.each do |key, value|
          if key == "default"
            unless value.kind_of?(Array)
              unless value.kind_of?(String)
                value = "#{value}"
              end
              value = [value]
            end
          end
          attr["option_#{key}"] = value
        end
      end
      #logger.debug("NEW HASH: #{hash.inspect}")
      hash.deep_transform_keys{ |key| key.to_s.tr('-', '_').gsub('attributes', 'profile_attributes').gsub(/\bid\b/, 'control_id') }
    end
end