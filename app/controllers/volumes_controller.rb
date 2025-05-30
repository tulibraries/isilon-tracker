class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show edit update destroy ]

  # GET /volumes or /volumes.json
  def index
    @volumes = Volume.all
  end

  # GET /volumes/1 or /volumes/1.json
  def show
  end

  # GET /volumes/new
  def new
    @volume = Volume.new
  end

  # GET /volumes/1/edit
  def edit
  end

  # POST /volumes or /volumes.json
  def create
    @volume = Volume.new(volume_params)

    respond_to do |format|
      if @volume.save
        format.html { redirect_to @volume, notice: "Volume was successfully created." }
        format.json { render :show, status: :created, location: @volume }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @volume.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /volumes/1 or /volumes/1.json
  def update
    respond_to do |format|
      if @volume.update(volume_params)
        format.html { redirect_to @volume, notice: "Volume was successfully updated." }
        format.json { render :show, status: :ok, location: @volume }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @volume.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /volumes/1 or /volumes/1.json
  def destroy
    @volume.destroy!

    respond_to do |format|
      format.html { redirect_to volumes_path, status: :see_other, notice: "Volume was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_volume
      @volume = Volume.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def volume_params
      params.fetch(:volume, {})
    end
end
