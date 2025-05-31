class IsilonAssetsController < ApplicationController
  before_action :set_isilon_asset, only: %i[ show edit update destroy ]

  # GET /isilon_assets or /isilon_assets.json
  def index
    @isilon_assets = IsilonAsset.all
  end

  # GET /isilon_assets/1 or /isilon_assets/1.json
  def show
  end

  # GET /isilon_assets/new
  def new
    @isilon_asset = IsilonAsset.new
  end

  # GET /isilon_assets/1/edit
  def edit
  end

  # POST /isilon_assets or /isilon_assets.json
  def create
    @isilon_asset = IsilonAsset.new(isilon_asset_params)

    respond_to do |format|
      if @isilon_asset.save
        format.html { redirect_to @isilon_asset, notice: "Isilon asset was successfully created." }
        format.json { render :show, status: :created, location: @isilon_asset }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @isilon_asset.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /isilon_assets/1 or /isilon_assets/1.json
  def update
    respond_to do |format|
      if @isilon_asset.update(isilon_asset_params)
        format.html { redirect_to @isilon_asset, notice: "Isilon asset was successfully updated." }
        format.json { render :show, status: :ok, location: @isilon_asset }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @isilon_asset.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /isilon_assets/1 or /isilon_assets/1.json
  def destroy
    @isilon_asset.destroy!

    respond_to do |format|
      format.html { redirect_to isilon_assets_path, status: :see_other, notice: "Isilon asset was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_isilon_asset
      @isilon_asset = IsilonAsset.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def isilon_asset_params
      params.fetch(:isilon_asset, {})
    end
end
