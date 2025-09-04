class IsilonAssetsController < ApplicationController
  def index
    @isilon_assets = IsilonAsset.all
  end
end
