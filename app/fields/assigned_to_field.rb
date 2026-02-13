class AssignedToField < Administrate::Field::BelongsTo
  def self.permitted_attribute(attr, _options = {})
    :"#{attr}_id"
  end

  def permitted_attribute
    :"#{attribute}_id"
  end
end
