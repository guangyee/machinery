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

describe Machinery::Cli do
  capture_machinery_output

  before(:all) do
    # Manually create the exclude option. It depends on the
    # experimental_features option, but that is evaluated when the class is
    # loaded, not when the test is run, so it can't be stubbed.
    unless Machinery::Cli.commands[:inspect].flags[:exclude]
      Machinery::Cli.commands[:inspect].flag :exclude, negatable: false,
        desc: "Exclude elements matching the filter criteria"
    end
    unless Machinery::Cli.commands[:show].flags[:exclude]
      Machinery::Cli.commands[:show].flag :exclude, negatable: false,
        desc: "Exclude elements matching the filter criteria"
    end
  end

  describe "#initialize" do
    before :each do
      allow_any_instance_of(IO).to receive(:puts)
    end

    it "sets the log level to :info by default" do
      run_command(["show"])

      expect(Machinery.logger.level).to eq(Logger::INFO)
    end

    it "sets the log level to :debug when the --debug option is given" do
      run_command(["--debug", "show"])

      expect(Machinery.logger.level).to eq(Logger::DEBUG)
    end
  end

  describe "#inspect-container" do
    let(:system) { double(start: nil, stop: nil) }
    before :each do
      allow_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
        and_return(create_test_description)
      allow(Machinery::SystemDescription).to receive(:delete)
      allow(Machinery::DockerSystem).to receive(:new).and_return(system)
    end

    it "calls the InspectTask" do
      expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
        with(
          an_instance_of(Machinery::SystemDescriptionStore),
          system,
          "docker_image_foo",
          an_instance_of(Machinery::CurrentUser),
          Machinery::Inspector.all_scopes,
          an_instance_of(Machinery::Filter),
          {}
        )

      run_command(["inspect-container", "docker_image_foo"])
    end

    it "aborts if the image and name contains slashes" do
      expect_any_instance_of(Machinery::InspectTask).not_to receive(:inspect_system)
      run_command(["inspect-container", "docker/foo"])
    end

    it "continues if only the image contains slashes" do
      expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
        with(
          an_instance_of(Machinery::SystemDescriptionStore),
          system,
          "docker_foo",
          an_instance_of(Machinery::CurrentUser),
          Machinery::Inspector.all_scopes,
          an_instance_of(Machinery::Filter),
          {}
        )

      run_command(["inspect-container", "docker/foo", "--name=docker_foo"])
    end
  end

  describe ".check_container_name!" do
    it "raises error if image and name contains slashes" do
      expect {
        Machinery::Cli.check_container_name!("docker/foo", "docker/foo")
      }.to raise_error(
        Machinery::Errors::InvalidCommandLine,
        /Error: System description name 'docker\/foo' is invalid\. By default Machinery uses the image name as description name if the parameter `--name` is not provided\.\nIf the image name contains a slash the `--name=NAME` parameter is mandatory. Valid characters are 'a-zA-Z0-9_:\.-'\./
      )
    end

    it "does not raise error if the name has no slashes" do
      expect {
        Machinery::Cli.check_container_name!("docker/foo", "docker_foo")
      }.not_to raise_error
    end
  end

  describe "#serve" do
    initialize_system_description_factory_store
    let(:store) { system_description_factory_store }

    it "triggers the serve task" do
      allow(Machinery::Cli).
        to receive(:system_description_store).and_return(store)
      expect_any_instance_of(Machinery::ServeHtmlTask).to receive(:serve).with(
        store, port: 3000, public: false
      )

      run_command(["serve", "--port=3000"])
    end

    it "checks if the --public option works" do
      allow(Machinery::Cli).
        to receive(:system_description_store).and_return(store)
      expect_any_instance_of(Machinery::ServeHtmlTask).to receive(:serve).with(
        store, port: 3000, public: true
      )

      run_command(["serve", "--port=3000", "--public"])
    end
  end

  context "machinery test directory" do
    include_context "machinery test directory"

    let(:example_host) { "myhost" }
    let(:description) {
      Machinery::SystemDescription.new("foo", Machinery::SystemDescriptionMemoryStore.new)
    }

    before(:each) do
      allow_any_instance_of(Machinery::SystemDescriptionStore).to receive(:default_path).
        and_return(test_base_path)
      create_machinery_dir
    end

    describe "#system_description_store" do
      it "returns the default store by default" do
        expect(Machinery::Cli.system_description_store.base_path).
          to eq(test_base_path)
      end

      it "uses the store specified by MACHINERY_DIR" do
        with_env("MACHINERY_DIR" => "/tmp/machinery") do
          expect(Machinery::Cli.system_description_store.base_path).
            to eq("/tmp/machinery")
        end
      end
    end

    describe "#inspect" do
      include_context "machinery test directory"

      before :each do
        allow_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          and_return(description)
        allow(Machinery::SystemDescription).to receive(:delete)
        allow_any_instance_of(Machinery::RemoteSystem).to receive(:connect)
      end

      it "shows a note if there are filters for the selected scopes" do
        run_command([
          "inspect", "--exclude=/os/name=bar", "description1", "--scope=os",
        ])

        expect(captured_machinery_output).
          to include("Note: There are filters being applied during "\
            "inspection. (Use `--verbose` option to show the filters)")
      end

      it "does not show a note unless any filters for the selected scopes are set" do
        run_command([
          "inspect", "--exclude=/foo=bar", "description1", "--scope=os",
        ])

        expect(captured_machinery_output).
          not_to include("Filters are applied during inspection.")
      end

      it "uses the provided host name if specified at the end" do
        expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          with(
            an_instance_of(Machinery::SystemDescriptionStore),
            an_instance_of(Machinery::RemoteSystem),
            example_host,
            an_instance_of(Machinery::CurrentUser),
            Machinery::Inspector.all_scopes,
            an_instance_of(Machinery::Filter),
            {}
          ).
          and_return(description)

        run_command(["inspect", example_host])
      end

      it "uses the provided name if specified with --name" do
        name = "test"
        expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          with(
            an_instance_of(Machinery::SystemDescriptionStore),
            an_instance_of(Machinery::RemoteSystem),
            name,
            an_instance_of(Machinery::CurrentUser),
            Machinery::Inspector.all_scopes,
            an_instance_of(Machinery::Filter),
            {}
           ).
           and_return(description)

        run_command(["inspect", "--name=#{name}", example_host])
      end

      it "uses the host name if no --name is provided" do
        expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          with(
            an_instance_of(Machinery::SystemDescriptionStore),
            an_instance_of(Machinery::RemoteSystem),
            example_host,
            an_instance_of(Machinery::CurrentUser),
            Machinery::Inspector.all_scopes,
            an_instance_of(Machinery::Filter),
            {}
           ).
          and_return(description)

        run_command(["inspect", example_host])
      end

      it "only inspects the scopes provided" do
        expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          with(
            an_instance_of(Machinery::SystemDescriptionStore),
            an_instance_of(Machinery::RemoteSystem),
            example_host,
            an_instance_of(Machinery::CurrentUser),
            ["packages", "repositories"],
            an_instance_of(Machinery::Filter),
            {}
          ).
          and_return(description)

        run_command(["inspect", "--scope=packages,repositories", example_host])
      end

      it "only inspects a scope once even if it was provided multiple times" do
        expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          with(
            an_instance_of(Machinery::SystemDescriptionStore),
            an_instance_of(Machinery::RemoteSystem),
            example_host,
            an_instance_of(Machinery::CurrentUser),
            ["packages"],
            an_instance_of(Machinery::Filter),
            {}
          ).
          and_return(description)

        run_command(["inspect", "--scope=packages,packages", example_host])
      end

      it "inspects all scopes if no --scope is provided" do
        expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          with(
            an_instance_of(Machinery::SystemDescriptionStore),
            an_instance_of(Machinery::RemoteSystem),
            example_host,
            an_instance_of(Machinery::CurrentUser),
            Machinery::Inspector.all_scopes,
            an_instance_of(Machinery::Filter),
            {}
          ).
          and_return(description)

        run_command(["inspect", example_host])
      end

      it "doesn't inspect the excluded scopes" do
        scope_list = Machinery::Inspector.all_scopes
        scope_list.delete("packages")
        scope_list.delete("repositories")

        expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
          with(
            an_instance_of(Machinery::SystemDescriptionStore),
            an_instance_of(Machinery::RemoteSystem),
            example_host,
            an_instance_of(Machinery::CurrentUser),
            scope_list,
            an_instance_of(Machinery::Filter),
            {}
          ).
          and_return(description)

        run_command(
          ["inspect", "--ignore-scope=packages,repositories", example_host]
        )
      end

      it "forwards the --skip-files option to the InspectTask as an unmanaged_files filter" do
        # rubocop:disable Style/SpaceAroundBlockParameters, Style/MultilineBlockLayout
        expect_any_instance_of(Machinery::InspectTask).
          to receive(:inspect_system) do |_instance,
                                          _store,
                                          _system,
                                          _name,
                                          _user,
                                          _scopes,
                                          filter,
                                          _options|
          expect(filter.element_filter_for("/unmanaged_files/name").matchers["="]).
            to include("/foo/bar", "/baz")
        end.and_return(description)
        # rubocop:enable Style/SpaceAroundBlockParameters, Style/MultilineBlockLayout

        run_command(["inspect", "--skip-files=/foo/bar,/baz", example_host])
      end

      it "forwards the global --exclude option to the InspectTask" do
        # rubocop:disable Style/SpaceAroundBlockParameters, Style/MultilineBlockLayout
        expect_any_instance_of(Machinery::InspectTask).
          to receive(:inspect_system) do |_instance,
                                          _store,
                                          _system,
                                          _name,
                                          _user,
                                          _scopes,
                                          filter,
                                          _options|
          expect(filter.element_filter_for("/unmanaged_files/files/name").matchers["="]).
            to include("/foo/bar")
        end.and_return(description)
        # rubocop:enable Style/SpaceAroundBlockParameters, Style/MultilineBlockLayout

        run_command([
          "inspect",
          "--exclude=/unmanaged_files/files/name=/foo/bar",
          example_host
        ])
      end

      it "adheres to the --remote-user option" do
        # rubocop:disable Style/SpaceAroundBlockParameters, Style/MultilineBlockLayout
        expect_any_instance_of(Machinery::InspectTask).
          to receive(:inspect_system) do |_instance,
                                          _store,
                                          system,
                                          _name,
                                          _user,
                                          _scopes,
                                          _filter,
                                          _options|
          expect(system.remote_user).to eq("foo")
        end.and_return(description)
        # rubocop:enable Style/SpaceAroundBlockParameters, Style/MultilineBlockLayout

        run_command([
          "inspect",
          "--remote-user=foo",
          example_host
        ])
      end

      describe "--verbose" do
        it "shows no filter message by default" do
          run_command([
            "inspect", example_host,
          ])

          expect(captured_machinery_output).
            not_to include(
              "The following filters are applied during inspection:"
            )
        end

        it "shows the filters when `--verbose` is provided" do
          run_command([
            "inspect", "--verbose", example_host,
          ])

          expect(captured_machinery_output).
            to include("The following filters are applied during inspection:")
          expect(captured_machinery_output).
            to match(/^\/unmanaged_files\/name=.*$/)
        end

        it "shows skip-files filters during inspection" do
          run_command([
            "inspect", "--skip-files=/baz ", "--verbose", example_host,
          ])

          expect(captured_machinery_output).
            to include("The following filters are applied during inspection:")
          expect(captured_machinery_output).
            to match(/\/baz/)
        end
      end

      describe "file extraction" do
        it "doesn't extract files when --extract-files is not specified" do
          expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
            with(
              an_instance_of(Machinery::SystemDescriptionStore),
              an_instance_of(Machinery::RemoteSystem),
              example_host,
              an_instance_of(Machinery::CurrentUser),
              Machinery::Inspector.all_scopes,
              an_instance_of(Machinery::Filter),
              {}
            ).
            and_return(description)

          run_command(["inspect", example_host])
        end

        it "extracts changed config/managed files and umanaged "\
            "files when --extract-files is specified" do
          expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
            with(
              an_instance_of(Machinery::SystemDescriptionStore),
              an_instance_of(Machinery::RemoteSystem),
              example_host,
              an_instance_of(Machinery::CurrentUser),
              Machinery::Inspector.all_scopes,
              an_instance_of(Machinery::Filter),
              extract_changed_changed_config_files: true,
              extract_unmanaged_files: true,
              extract_changed_managed_files: true
            ).
            and_return(description)

          run_command(["inspect", "--extract-files", example_host])
        end

        it "extracts only changed config files when --extract-changed-config-files is specified" do
          expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
            with(
              an_instance_of(Machinery::SystemDescriptionStore),
              an_instance_of(Machinery::RemoteSystem),
              example_host,
              an_instance_of(Machinery::CurrentUser),
              Machinery::Inspector.all_scopes,
              an_instance_of(Machinery::Filter),
              extract_changed_changed_config_files: true
            ).
            and_return(description)

          run_command(["inspect", "--extract-changed-config-files", example_host])
        end

        it "extracts only umanaged files when --extract-unmanaged-files is specified" do
          expect_any_instance_of(Machinery::InspectTask).to receive(:inspect_system).
            with(
              an_instance_of(Machinery::SystemDescriptionStore),
              an_instance_of(Machinery::RemoteSystem),
              example_host,
              an_instance_of(Machinery::CurrentUser),
              Machinery::Inspector.all_scopes,
              an_instance_of(Machinery::Filter),
              extract_unmanaged_files: true
            ).
            and_return(description)

          run_command(["inspect", "--extract-unmanaged-files", example_host])
        end
      end
    end

    describe "#build" do
      it "triggers a build" do
        path = "/tmp/output_path"
        description = create_test_description(json: test_manifest)
        description.name = "descriptionx"

        expect_any_instance_of(Machinery::BuildTask).to receive(:build).
          with(description, path, enable_dhcp: false, enable_ssh: false)

        run_command(["build", "description1", "--image-dir=#{path}"])
      end
    end

    describe "#show" do
      it "triggers the show task for packages when scope packages is specified" do
        description = create_test_description(json: test_manifest)
        expect_any_instance_of(Machinery::ShowTask).
          to receive(:show).with(
            description,
            ["packages"],
            an_instance_of(Machinery::Filter),
            show_diffs: false,
            show_html:  false,
            ip:         "127.0.0.1",
            port:       anything
          )

        run_command(["show", "description1", "--scope=packages", "--no-pager"])
      end

      describe "--verbose" do
        before(:each) do
          expect_any_instance_of(Machinery::ShowTask).to receive(:show)
        end

        it "shows no filter message by default" do
          run_command([
            "show", "description1",
          ])

          expect(captured_machinery_output).
            not_to include("The following filters were applied before showing the description:")
        end

        it "shows the filters when `--verbose` is provided" do
          run_command(
            [
              "show",
              "description1",
              "--exclude=/unmanaged_files/files/name=/foo",
              "--verbose",
            ]
          )

          expect(captured_machinery_output).
            to match(/  The following filters were applied before showing the description:/)
          expect(captured_machinery_output).
            to match(/^    \* \/unmanaged_files\/files\/name=.*$/)
        end

        it "shows the filters which are applied during inspection" do
          description = Machinery::SystemDescription.load(
            "description1",
            Machinery::SystemDescriptionStore.new
          )
          description.set_filter_definitions("inspect", ["/foo=bar"])
          description.save

          run_command([
            "show", "description1", "--verbose",
          ])

          expect(captured_machinery_output).
            to match(/^  The following filters were applied during inspection:/)
          expect(captured_machinery_output).
            to match(/^    \* \/foo=bar/)
        end

        context "when the inspected system was a docker container" do
          let(:test_manifest) { create_test_description(scopes: ["docker_environment"]).to_json }

          it "displays docker" do
            run_command([
              "show", "description1", "--verbose"
            ])

            expect(captured_machinery_output).
              to include("  Type of inspected container: docker")
          end
        end
      end
    end

    describe "#validate" do
      it "triggers a validation" do
        name = "description1"
        expect_any_instance_of(Machinery::ValidateTask).
          to receive(:validate).with(
            an_instance_of(Machinery::SystemDescriptionStore), name
          )

        run_command(["validate", "description1"])
      end
    end

    describe "#export_kiwi" do
      before(:each) do
        @kiwi_config = double
        allow(Machinery::KiwiConfig).to receive(:new).and_return(@kiwi_config)
      end

      it "triggers a KIWI export" do
        expect_any_instance_of(Machinery::ExportTask).to receive(:export).
          with("/tmp/export", force: false)

        run_command(["export-kiwi", "description1", "--kiwi-dir=/tmp/export"])
      end

      it "forwards the force option" do
        expect_any_instance_of(Machinery::ExportTask).to receive(:export).
          with("/tmp/export", force: true)

        run_command(
          ["export-kiwi", "description1", "--kiwi-dir=/tmp/export", "--force"]
        )
      end
    end

    describe "#export_autoyast" do
      before(:each) do
        @autoyast = double
        allow(Machinery::Autoyast).to receive(:new).with(instance_of(Machinery::SystemDescription)).
          and_return(@autoyast)
      end

      it "triggers a AutoYaST export" do
        expect_any_instance_of(Machinery::ExportTask).to receive(:export).
          with("/tmp/export", force: false)

        run_command(
          ["export-autoyast", "description1", "--autoyast-dir=/tmp/export"]
        )
      end

      it "forwards the force option" do
        expect_any_instance_of(Machinery::ExportTask).to receive(:export).
          with("/tmp/export", force: true)

        run_command(
          [
            "export-autoyast",
            "description1",
            "--autoyast-dir=/tmp/export",
            "--force"
          ]
        )
      end
    end

    describe "#analyze" do
      it "fails when an unsupported operation is called" do
        create_test_description(json: test_manifest)

        run_command(["analyze", "description1", "--operation=foo"])
        expect(captured_machinery_stderr).
          to include("The operation 'foo' is not supported")
      end

      it "triggers the analyze task" do
        description = create_test_description(json: test_manifest)
        expect_any_instance_of(Machinery::AnalyzeConfigFileDiffsTask).
          to receive(:analyze).with(
            description
          )

        run_command(
          ["analyze", "description1", "--operation=changed-config-files-diffs"]
        )
      end

      it "runs changed-config-files-diffs by default" do
        description = create_test_description(json: test_manifest)
        expect_any_instance_of(Machinery::AnalyzeConfigFileDiffsTask).
          to receive(:analyze).with(
            description
          )

        run_command(["analyze", "description1"])
      end
    end
  end

  describe "#remove" do
    it "triggers the remove task" do
      expect_any_instance_of(Machinery::RemoveTask).to receive(:remove).
        with(an_instance_of(Machinery::SystemDescriptionStore), ["foo"], anything)

      run_command(["remove", "foo"])
    end

    it "triggers the remove task with --all option if given" do
      expect_any_instance_of(Machinery::RemoveTask).to receive(:remove).
        with(
          an_instance_of(Machinery::SystemDescriptionStore),
          anything,
          verbose: false,
          all:     true
        )

      run_command(["remove", "--all"])
    end
  end

  describe "#list" do
    it "triggers the list task" do
      expect_any_instance_of(Machinery::ListTask).to receive(:list).
        with(an_instance_of(Machinery::SystemDescriptionStore), anything, anything)
      run_command(["list"])
    end

    it "triggers the list task with --html switch" do
      expect_any_instance_of(Machinery::ListTask).
        to receive(:list) do |_instance, _store, _description, options|
          expect(options[:html]).to eq(true)
        end
      run_command(["list", "--html"])
    end
  end

  describe "#man" do
    it "triggers the man task" do
      expect_any_instance_of(Machinery::ManTask).to receive(:man)

      run_command(["man"])
    end
  end

  describe "#copy" do
    it "triggers the copy task" do
      expect_any_instance_of(Machinery::CopyTask).to receive(:copy).
        with(an_instance_of(Machinery::SystemDescriptionStore), "foo", "bar")
      run_command(["copy", "foo", "bar"])
    end
  end

  describe "#move" do
    it "triggers the move task" do
      expect_any_instance_of(Machinery::MoveTask).to receive(:move).
        with(an_instance_of(Machinery::SystemDescriptionStore), "foo", "bar")
      run_command(["move", "foo", "bar"])
    end
  end

  describe "#upgrade_format" do
    it "triggers the upgrade task for a specific description" do
      expect_any_instance_of(Machinery::UpgradeFormatTask).to receive(:upgrade).
        with(
          an_instance_of(Machinery::SystemDescriptionStore),
          "foo",
          all:   false,
          force: false
        )
      run_command(["upgrade-format", "foo"])
    end

    it "triggers the upgrade task for all descriptions" do
      expect_any_instance_of(Machinery::UpgradeFormatTask).to receive(:upgrade).
        with(
          an_instance_of(Machinery::SystemDescriptionStore),
          nil,
          all:   true,
          force: false
        )
      run_command(["upgrade-format", "--all"])
    end

    it "triggers the upgrade task with force option" do
      expect_any_instance_of(Machinery::UpgradeFormatTask).to receive(:upgrade).
        with(
          an_instance_of(Machinery::SystemDescriptionStore),
          "foo",
          all:   false,
          force: true
        )
      run_command(["upgrade-format", "--force", "foo"])
    end
  end

  describe "#config" do
    it "triggers the config task" do
      expect_any_instance_of(Machinery::ConfigTask).to receive(:config).
        with("foo", "bar")
      run_command(["config", "foo", "bar"])
    end

    it "handles parameter with equal sign syntax" do
      expect_any_instance_of(Machinery::ConfigTask).to receive(:config).
        with("foo", "bar")
      run_command(["config", "foo=bar"])
    end
  end

  describe ".process_scope_option" do
    it "returns the scopes which are provided" do
      expect(Machinery::Cli.process_scope_option("os,packages", nil)).
        to eq(["os", "packages"])
    end

    it "returns sorted scope list" do
      expect(Machinery::Cli.process_scope_option("packages,users,os", nil)).
        to eq(["os", "packages", "users"])
    end

    it "returns all scopes if no scopes are provided" do
      expect(Machinery::Cli.process_scope_option(nil, nil)).
        to eq(Machinery::Inspector.all_scopes)
    end

    it "returns all scopes except the excluded scope" do
      scope_list = Machinery::Inspector.all_scopes
      scope_list.delete("os")
      expect(Machinery::Cli.process_scope_option(nil, "os")).to eq(scope_list)
    end

    it "raises an error if both scopes and excluded scopes are given" do
      expect { Machinery::Cli.process_scope_option("scope1", "scope2") }.
        to raise_error(Machinery::Errors::InvalidCommandLine)
    end
  end

  describe ".parse_scopes" do
    it "returns an array with existing scopes" do
      expect(Machinery::Cli.parse_scopes("os,changed-config-files")).
        to eq(["os", "changed_config_files"])
    end

    context "if the old scope name config-files is used" do
      it "shows a deprecated warning" do
        expect(Machinery::Ui).to receive(:warn).with(
          "The scope name `config-files` is deprecated. The new name is `changed-config-files`."
        )
        Machinery::Cli.parse_scopes("config-files")
      end

      it "does not raise" do
        expect { Machinery::Cli.parse_scopes("config-files") }.
          not_to raise_error
      end

      it "returns the scope name changed-config-files instead" do
        expect(Machinery::Cli.parse_scopes("config-files")).
          to eq(["changed_config_files"])
      end
    end

    it "raises an error if the provided scope is unknown" do
      expect {
        Machinery::Cli.parse_scopes("unknown-scope")
      }.to raise_error(Machinery::Errors::UnknownScope, /unknown-scope/)
    end

    it "uses singular in the error message for one scope" do
      expect {
        Machinery::Cli.parse_scopes("unknown-scope")
      }.to raise_error(
        Machinery::Errors::UnknownScope,
        /The following scope is not supported: unknown-scope./
      )
    end

    it "uses plural in the error message for more than one scope" do
      expect {
        Machinery::Cli.parse_scopes("unknown-scope,unknown-scope2")
      }.to raise_error(
        Machinery::Errors::UnknownScope,
        /The following scopes are not supported: unknown-scope, unknown-scope2./
      )
    end

    it "raises an error if the scope contains illegal characters" do
      expect {
        Machinery::Cli.parse_scopes("fd df,u*n")
      }.to raise_error(Machinery::Errors::UnknownScope,
        /The following scopes are not valid: 'fd df', 'u\*n'\./)
    end
  end

  describe ".handle_error" do
    context "for options" do
      option_parser_exceptions = [OptionParser::MissingArgument, OptionParser::AmbiguousOption]

      option_parser_exceptions.each do |error|
        it "shows a proper error-message for [#{error}]" do
          begin
            raise(error.new)
          rescue => e
            expect { Machinery::Cli.handle_error(e) }.to raise_error(SystemExit)
          end
          expect(captured_machinery_stderr).to include(
            e.to_s, "Run '#{$0}", "--help' for more information."
          )
        end
      end
    end

    it "shows stderr, stdout and the backtrace for unexpected errors" do
      expected_cheetah_out = <<-EOT.chomp
Machinery experienced an unexpected error.
If this impacts your business please file a service request at https://www.suse.com/mysupport
so that we can assist you on this issue. An active support contract is required.

Cheetah::ExecutionFailed

Error output:
This is STDERR
Standard output:
This is STDOUT

Backtrace:
      EOT

      allow(Machinery::LocalSystem).to receive(:os).and_return(Machinery::OsSles12.new)
      begin
        # Actually raise the exception, so we have a backtrace
        raise(
          Cheetah::ExecutionFailed.new(
            nil,
            nil,
            "This is STDOUT",
            "This is STDERR"
          )
        )
      rescue => e
        expect { Machinery::Cli.handle_error(e) } .to raise_error(SystemExit)
      end
      expect(captured_machinery_stderr).to include(expected_cheetah_out)
    end

    it "shows the usual bug report message for openSUSE" do
      allow(Machinery::LocalSystem).to receive(:os).and_return(Machinery::OsOpenSuse13_1.new)

      begin
        raise
      rescue => e
        expect { Machinery::Cli.handle_error(e) }.to raise_error
      end

      expect(captured_machinery_output).to include(
        "Machinery experienced an unexpected error. Please file a " \
        "bug report at: https://github.com/SUSE/machinery/issues/new\n"
      )
    end

    it "shows a special bug report message for SLES" do
      allow(Machinery::LocalSystem).to receive(:os).and_return(Machinery::OsSles12.new)

      begin
        raise
      rescue => e
        expect { Machinery::Cli.handle_error(e) } .to raise_error
      end

      expect(captured_machinery_output).to include(
        "Machinery experienced an unexpected error.\n" \
        "If this impacts your business please file a service request at " \
        "https://www.suse.com/mysupport\n" \
        "so that we can assist you on this issue. An active support "\
        "contract is required.\n"
      )
    end
  end

  describe ".check_port_validity" do
    it "checks if a port is invalid below 2" do
      expect { Machinery::Cli.check_port_validity(1) }.to raise_error(
        Machinery::Errors::ServerPortError
      )
    end

    it "checks if a port is invalid above 65535" do
      expect { Machinery::Cli.check_port_validity(65536) }.to raise_error(
        Machinery::Errors::ServerPortError
      )
    end

    it "checks if a port is valid between 2 and 65535" do
      expect { Machinery::Cli.check_port_validity(5000) }.to_not raise_error
    end

    it "checks if a port requires root privileges" do
      expect { Machinery::Cli.check_port_validity(1000) }.to raise_error(
        Machinery::Errors::ServerPortError
      )
    end
  end

  private

  def run_command(*args)
    Machinery::Cli.run(*args)
  rescue SystemExit
  end
end
