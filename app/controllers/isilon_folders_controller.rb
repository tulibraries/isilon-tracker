class IsilonFoldersController < ApplicationController
  before_action :set_isilon_folder, only: %i[ show edit update destroy ]

  # GET /isilon_folders or /isilon_folders.json
  def index
    @isilon_folders = IsilonFolder.all
  end

  # GET /isilon_folders/1 or /isilon_folders/1.json
  def show
  end

  # GET /isilon_folders/new
  def new
    @isilon_folder = IsilonFolder.new
  end

  # GET /isilon_folders/1/edit
  def edit
  end

  # POST /isilon_folders or /isilon_folders.json
  def create
    @isilon_folder = IsilonFolder.new(isilon_folder_params)

    respond_to do |format|
      if @isilon_folder.save
        format.html { redirect_to @isilon_folder, notice: "Isilon folder was successfully created." }
        format.json { render :show, status: :created, location: @isilon_folder }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @isilon_folder.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /isilon_folders/1 or /isilon_folders/1.json
  def update
    respond_to do |format|
      if @isilon_folder.update(isilon_folder_params)
        format.html { redirect_to @isilon_folder, notice: "Isilon folder was successfully updated." }
        format.json { render :show, status: :ok, location: @isilon_folder }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @isilon_folder.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /isilon_folders/1 or /isilon_folders/1.json
  def destroy
    @isilon_folder.destroy!

    respond_to do |format|
      format.html { redirect_to isilon_folders_path, status: :see_other, notice: "Isilon folder was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_isilon_folder
      @isilon_folder = IsilonFolder.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def isilon_folder_params
      params.fetch(:isilon_folder, {})
    end
end
