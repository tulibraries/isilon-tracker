require "administrate/field/has_many"

# Custom Administrate field that surfaces other assets sharing the same
# checksum as the current record. We reuse the HasMany table rendering while
# swapping in a checksum-based query instead of the `duplicate_of` relation.
class ChecksumDuplicatesField < Administrate::Field::HasMany
  def data
    @checksum_duplicates ||= begin
      checksum = resource.file_checksum
      if checksum.blank?
        associated_class.none
      else
        associated_class
          .where(file_checksum: checksum)
          .where.not(id: resource.id)
          .order(:isilon_name)
      end
    end
  end

  def associated_class
    IsilonAsset
  end

  private

  def associated_dashboard
    @associated_dashboard ||= IsilonAssetDashboard.new
  end
end
