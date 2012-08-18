# Copyright (c) 2011, 2012 Solano Labs All Rights Reserved

module Tddium
  class TddiumCli < Thor
    desc "logout", "Log out of tddium"
    def logout
      tddium_setup({:login => false, :git => false})

      @api_config.logout

      say Text::Process::LOGGED_OUT_SUCCESSFULLY
    end
  end
end
