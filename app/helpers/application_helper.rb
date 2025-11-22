module ApplicationHelper
  def nav_link_classes(active = false)
    base_classes = "flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium transition-all"
    if active
      "#{base_classes} bg-white bg-opacity-10 text-white"
    else
      "#{base_classes} text-gray-300 hover:bg-white hover:bg-opacity-5"
    end
  end
end
