# frozen_string_literal: true

module Web
  module SalesLedger
    class ImportsController < ApplicationController
      def index
        @imports = ::SalesLedger::SalesImport.recent.limit(50)
      end

      def create
        file = params[:file]

        unless file
          redirect_to web_sales_ledger_imports_path, alert: "Seleccioná un archivo CSV para importar"
          return
        end

        result = ::SalesLedger::ImportCsv.call(
          file: file,
          filename: file.original_filename
        )

        if result.success?
          import = result.record
          redirect_to web_sales_ledger_import_path(import),
                      notice: "Importación completada: #{import.created_entries_count} filas importadas, #{import.created_products_count} productos nuevos"
        else
          redirect_to web_sales_ledger_imports_path,
                      alert: "No se pudo importar el archivo: #{result.errors.join(', ')}"
        end
      end

      def show
        @import  = ::SalesLedger::SalesImport.find(params[:id])
        @entries = @import.entries
                          .order(:sale_date, :ticket_number)
                          .page(params[:page]).per(50)
      end
    end
  end
end
