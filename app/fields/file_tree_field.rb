require "administrate/field/base"

class FileTreeField < Administrate::Field::Base
  def to_s
    data
  end
end
