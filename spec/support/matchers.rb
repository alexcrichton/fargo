RSpec::Matchers.define :have_contents do |contents|
  match do |file|
    File.file?(file) && File.read(file).chomp.should == contents.chomp
  end

  failure_message do |file|
    msg = "Expected #{file} to contain:\n\t#{contents.gsub("\n", "\n\t")}\nWhen"

    if File.file?(file)
      msg += " it contained:\n#{File.read(file)}".gsub("\n", "\n\t")
    else
      msg += ' it did not exist.'
    end

    msg
  end
end
