class RemoveUniqueIndexToDocumentAssociations < ActiveRecord::Migration[4.2]
  def change
    remove_index :document_associations, 
      column: [:document_id, :associable_id, :associable_type], 
      name: "index_document_associations_unique_document_id_associable",
      unique: true
    add_index :document_associations, [:document_id, :associable_id, :associable_type], 
      name: "index_document_associations_document_id_associable",
      unique: false
  end
end
