module ApplicationHelper
  include Pagy::Frontend
  PRODUCT_SOURCE_BADGE_CLASSES = {
    "local"     => "bg-emerald-100 text-emerald-800",
    "importado" => "bg-blue-100 text-blue-800"
  }.freeze

  PRODUCT_SOURCE_LABELS = {
    "local"     => "Local",
    "importado" => "Importado"
  }.freeze

  PAYMENT_METHOD_BADGE_CLASSES = {
    "cash"          => "bg-green-900 text-white",  # dark green
    "bank_qr"       => "bg-blue-900 text-white",   # dark blue
    "bank_card"     => "bg-blue-900 text-white",
    "bank_transfer" => "bg-blue-900 text-white",
    "bank"          => "bg-blue-900 text-white",   # ledger (cash/bank/mercado_pago)
    "mercado_pago"  => "bg-sky-400 text-white"     # light blue
  }.freeze

  # Delegates to the Payment model catalog and adds "bank" for the
  # Sales Ledger views (subsystem with its own set of methods).
  PAYMENT_METHOD_LABELS = Payment::PAYMENT_METHOD_LABELS.merge("bank" => "Banco").freeze

  def product_source_badge_class(source)
    PRODUCT_SOURCE_BADGE_CLASSES.fetch(source.to_s, "bg-slate-100 text-slate-700").html_safe
  end

  def product_source_label(source)
    PRODUCT_SOURCE_LABELS.fetch(source.to_s, source.to_s.humanize)
  end

  def payment_method_badge_class(method)
    PAYMENT_METHOD_BADGE_CLASSES.fetch(method.to_s, "bg-slate-100 text-slate-700").html_safe
  end

  def payment_method_label(method)
    PAYMENT_METHOD_LABELS.fetch(method.to_s, method.to_s.humanize)
  end

  def nav_link_classes(active = false)
    base_classes = "flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium transition-all"
    if active
      "#{base_classes} bg-white bg-opacity-10 text-white"
    else
      "#{base_classes} text-gray-300 hover:bg-white hover:bg-opacity-5"
    end
  end

  # Helper to check whether the current controller matches any of the given names
  # Supports multiple controllers and optional actions
  def active_class(*controller_names)
    controllers = controller_names.flatten.map(&:to_s)

    # Check whether any of them matches
    if controllers.any? { |name| controller_name == name }
      "active"
    else
      ""
    end
  end

  # Helper to generate sorting links in tables
  # Parameters:
  #   column: name of the column to sort by
  #   title: text to display in the header
  #   current_params: current request parameters
  def sortable_column(column, title, current_params)
    direction = if current_params[:sort] == column.to_s && current_params[:direction] == "asc"
      "desc"
    else
      "asc"
    end

    # Keep other filter parameters (q, category, status)
    link_params = {
      q: current_params[:q],
      category: current_params[:category],
      status: current_params[:status],
      sort: column,
      direction: direction
    }.compact

    link_to web_products_path(link_params), class: "flex items-center gap-1.5 hover:text-slate-700 transition-colors" do
      content = content_tag(:span, title)

      # Show arrow if this column is active
      if current_params[:sort] == column.to_s
        arrow = if current_params[:direction] == "asc"
          content_tag(:span, "↑", class: "text-slate-700 font-semibold")
        else
          content_tag(:span, "↓", class: "text-slate-700 font-semibold")
        end
        content + arrow
      else
        # Show double arrow if not sorting by this column
        content + content_tag(:span, "↕", class: "text-slate-400")
      end
    end
  end
end
