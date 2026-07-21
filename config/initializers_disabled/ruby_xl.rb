module RubyXL
  module CellConvenienceMethods
    def change_value(data)
      self.change_contents(data)
      self.formula = nil
      self.datatype = nil
      workbook.calculation_chain.cells.select! { |c|
        !(c.ref.col_range.begin == self.column && c.ref.row_range.begin == self.row)
      }

      data
    end
  end
end