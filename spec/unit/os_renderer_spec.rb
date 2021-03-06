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

require_relative "spec_helper"

describe Machinery::Ui::OsRenderer do
  let(:system_description) {
    create_test_description(json: <<-EOF)
    {
      "os": {
      "name": "openSUSE 13.1 (Bottle)",
      "version": "13.1",
      "architecture": "x86_64"
      }
    }
    EOF
  }

  describe "show" do
    it "prints operation system information" do
      expected_output = <<-EOF
# Operating System

  Name: openSUSE 13.1 (Bottle)
  Version: 13.1
  Architecture: x86_64

EOF
      expect(Machinery::Ui::OsRenderer.new.render(system_description)).to eq(expected_output)
    end
  end
end
