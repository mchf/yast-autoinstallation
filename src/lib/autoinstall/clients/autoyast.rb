# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"

module Y2Autoinstallation
  module Clients
    class Autoyast < Yast::Client
      include Yast::Logger

      def initialize
        textdomain "autoinst"

        Yast.import "Pkg"
        Yast.import "Wizard"
        Yast.import "Mode"
        Yast::Mode.SetMode("autoinst_config")

        Yast.import "Profile"
        Yast.import "AutoinstConfig"
        Yast.import "Y2ModuleConfig"
        Yast.import "Sequencer"
        Yast.import "Popup"
        Yast.import "AddOnProduct"
        Yast.import "CommandLine"
        Yast.import "AutoInstall"

        Yast.include self, "autoinstall/dialogs.rb"
        Yast.include self, "autoinstall/conftree.rb"
        Yast.include self, "autoinstall/wizards.rb"
      end

      def main
        if Yast::Y2ModuleConfig.GroupMap.empty?
          Yast::Wizard.CreateDialog
          Yast::Popup.Error(_("Error while reading configuration data."))
          Yast::Wizard.CloseDialog
          return :abort
        end

        Yast::Pkg.CallbackImportGpgKey(
          fun_ref(
            Yast::AutoInstall.method(:callbackTrue_boolean_map_integer),
            "boolean (map <string, any>, integer)"
          )
        )
        Yast::Pkg.CallbackAcceptUnknownGpgKey(
          fun_ref(
            Yast::AutoInstall.method(:callbackTrue_boolean_string_string_integer),
            "boolean (string, string, integer)"
          )
        )
        Yast::Pkg.CallbackAcceptFileWithoutChecksum(
          fun_ref(
            Yast::AutoInstall.method(:callbackTrue_boolean_string),
            "boolean (string)"
          )
        )
        Yast::Pkg.CallbackAcceptUnsignedFile(
          fun_ref(
            Yast::AutoInstall.method(:callbackTrue_boolean_string_integer),
            "boolean (string, integer)"
          )
        )

        @cmdline = {
          "id"         => "autoyast2",
          "help"       => _("AutoYaST"),
          "guihandler" => fun_ref(method(:AutoSequence), "any ()"),
          "actions"    => {
            "file"   => {
              "handler" => fun_ref(
                method(:openFile),
                "boolean (map <string, string>)"
              ),
              "help"    => "file operations"
            },
            "module" => {
              "handler" => fun_ref(
                method(:runModule),
                "boolean (map <string, string>)"
              ),
              "help"    => "module specific operations"
            }
          },
          "options"    => {
            "filename" => { "type" => "string", "help" => "filename=XML_PROFILE" },
            "modname"  => { "type" => "string", "help" => "modname=AYAST_MODULE" }
          },
          "mappings"   => { "file" => ["filename"], "module" => ["modname"] }
        }

        # command line options
        # Init variables
        @command = ""
        @flags = []
        @options = {}
        @exit = ""
        @l = []

        @ret = nil
        @ret = Yast::CommandLine.Run(@cmdline)

        Yast::AddOnProduct.CleanModeConfigSources
        :exit
      end

      def openFile(options)
        if !Yast::Profile.ReadXML(options.fetch("filename", ""))
          Yast::Popup.Error(
            _(
              "Error while parsing the control file.\n" \
                "Check the log files for more details or fix the\n" \
                "control file and try again.\n"
            )
          )
        end
        Yast::Popup.ShowFeedback(
          _("Reading configuration data"),
          _("This may take a while")
        )
        Yast::Profile.ModuleMap.each do |name, values|
          # Set resource name, if not using default value
          resource = values.fetch("X-SuSE-YaST-AutoInstResource", name)
          log.debug("resource: #{resource}")
          module_auto = values.fetch("X-SuSE-YaST-AutoInstClient", "none")
          rd = Yast::Y2ModuleConfig.getResourceData(values, resource)
          Yast::WFM.CallFunction(module_auto, ["Import", rd]) unless rd.nil?
        end
        Yast::Popup.ClearFeedback
        AutoSequence()
        true
      end

      def runModule(options)
        Yast::AutoinstConfig.runModule = options["modname"] || ""
        AutoSequence()
        true
      end
    end
  end
end
