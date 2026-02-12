class GpsLocationPartition < ApplicationRecord
  
  after_destroy :destroy_partition

  def self.archilve_old_data
    min_date = Date.today - (ApplicationSetting.cad_avl_data_storage_months || 1).months
    min_year = min_date.year 
    min_month = min_date.month

    GpsLocationPartition.where("year < ? OR (year = ? AND month <= ?)", min_year, min_year, min_month).destroy_all
  end

  private

  def archive_partition
     # archive data to csv
    archive_folder = "#{Rails.root}/public/cad_avl_data_archives"
    file_path = "#{archive_folder}/#{self.provider_id}_#{self.year}_#{self.month}.csv"
    sql = "COPY #{self.table_name} TO '#{file_path}' DELIMITER ',' CSV HEADER;"
    ActiveRecord::Base.connection.execute(sql) rescue nil

    true
  end

  def destroy_partition
    # delete index and table
    index_name = self.table_name + "_provider_logtime_idx"

    partition_sql = <<-SQL
      DROP INDEX IF EXISTS #{index_name};
      DROP TABLE IF EXISTS #{self.table_name};
    SQL
    
    ActiveRecord::Base.connection.execute partition_sql

    true
  end

end
