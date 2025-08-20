class IsilonFoldersController < ApplicationController
  def index
    @isilon_folders = IsilonFolder.all
  end
end
