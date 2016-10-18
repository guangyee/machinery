# Copyright (c) 2013-2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 3 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact SUSE LLC.
#
# To contact SUSE about this file by physical or electronic mail,
# you may find current contact information at www.suse.com

#  This renderer prints the operating system
class OsRenderer < Machinery::Ui::Renderer
  def content(description)
    return unless description.os

    puts "Name: #{description.os.name}"
    puts "Version: #{description.os.version}"
    puts "Architecture: #{description.os.architecture}"
  end

  def display_name
    "Operating System"
  end
end
