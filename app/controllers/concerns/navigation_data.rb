module NavigationData
  extend ActiveSupport::Concern

  included do
    before_action :set_navigation_data
  end

  private

  def set_navigation_data
    @navigation_collections = collection_models_with_data
    @navigation_volumes = Volume.exists? ? Volume.all : []
  end

  def collection_models_with_data
    collection_model_names = %w[AspaceCollection ContentdmCollection]

    collection_model_names.filter_map do |model_name|
      model_class = model_name.constantize
      next unless model_class.exists?

      {
        name: model_class.model_name.human,
        path: polymorphic_path([:admin, model_class]),
        url_prefix: polymorphic_path([:admin, model_class]),
        model: model_class
      }
    rescue NameError
      nil
    end
  end
end
