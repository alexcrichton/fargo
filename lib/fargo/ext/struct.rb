class Struct
  def to_h
    {}.tap do |h|
      members.zip(entries).each{ |k, v| h[k] = v }
    end
  end
end
