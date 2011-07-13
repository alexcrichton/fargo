class Struct
  # Serialize a struct into a hash where the keys are the members of the struct
  # and the values are their corresponding entries.
  def to_h
    {}.tap do |h|
      members.zip(entries).each{ |k, v| h[k] = v }
    end
  end
end
