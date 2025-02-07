#
# read_mentor_list.rb
# Copyright (C) 2015 Daisuke Shimamoto <shimamoto@lifeistech.co.jp>
#
# All Rights Reserved.
#

require 'optparse'
require 'simple_xlsx_reader'

require 'google_utils'
require 'seed_utility'
require 'data_utils'
require 'camp_application_xlsx_reader'

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [-g] xlsx_file_path"
  opts.on('--dry-run', 'Dry run') { |x| dry_run = x }
end.parse!

if ARGV.length < 1
  puts 'Please specify an Excel file.'
  exit(-1)
end

file_path = ARGV[0]

reader = CampApplicationXlsxReader.new(file_path, execute: options[:dry_run])

reader.read_applications
