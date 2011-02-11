# Copyright (c) 2010 Sauce Labs Inc
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

ActiveRecord::Base.instance_eval do
  unless self.const_defined?("SpecStormLoaded")
    puts "Patching ActiveRecord::Base"
    SpecStormLoaded = true

    def prefix_and_reset_all_table_names_to(prefix)
      ActiveRecord::Base.table_name_prefix = prefix
      ActiveRecord::Base.reset_all_table_names
    end
    
    def reset_all_table_names
      subclasses.each do |sc|
        sc.reset_table_name
        puts "Reset #{sc}..."
      end
    end

    def show_all_subclasses
      subclasses.each do |sc|
        puts "#{sc} -> #{sc.table_name}"
      end
    end
  end
end
