Result = Struct.new(:success?, :record, :errors, keyword_init: true) do
  def failure?
    !success?
  end
end
