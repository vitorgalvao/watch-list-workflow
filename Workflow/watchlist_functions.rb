#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'open3'

Lists_dir = ENV['lists_dir'].empty? ? ENV['alfred_workflow_data'] : ENV['lists_dir']
Lists_file = "#{Lists_dir}/watchlist.json".freeze
Maximum_watched = Integer(ENV['maximum_watched'])
Quick_playlist = File.join(ENV['alfred_workflow_cache'], 'quick_playlist.txt')
Move_when_adding = !ENV['move_on_add'].empty?
Prepend_new = ENV['prepend_new_item'] == '1'
Trash_on_watched = ENV['trash_on_watched'] == '1'
Top_on_play = ENV['top_on_play'] == '1'
Prefer_action_url = ENV['prefer_action_url'] == '1'

FileUtils.mkpath(Lists_dir) unless Dir.exist?(Lists_dir)
FileUtils.mkpath(File.dirname(Quick_playlist)) unless Dir.exist?(File.dirname(Quick_playlist))
File.write(Lists_file, { towatch: [], watched: [] }.to_json) unless File.exist?(Lists_file)

def move_to_dir(path, target_dir)
  path_name = File.basename(path)
  target_path = File.join(target_dir, path_name)

  if File.dirname(path) == target_dir
    warn 'Path is already at target directory'
  elsif File.exist?(target_path)
    error('Can’t move because another target with the same name already exists')
  else
    File.rename(path, target_path)
  end

  target_path
end

def add_local_to_watchlist(path, id = random_hex, allow_move = true)
  require_audiovisual(path)

  target_path = Move_when_adding && allow_move ? move_to_dir(path, File.expand_path(ENV['move_on_add'])) : path

  if File.file?(target_path)
    add_file_to_watchlist(target_path, id)
  elsif File.directory?(target_path)
    add_dir_to_watchlist(target_path, id)
  else
    error('Not a valid path')
  end
end

def add_file_to_watchlist(file_path, id = random_hex)
  name = File.basename(file_path, File.extname(file_path))

  duration_machine = duration_in_seconds(file_path)
  duration_human = seconds_to_hms(duration_machine)

  size_machine = Open3.capture2('du', file_path).first.to_i
  size_human = Open3.capture2('du', '-h', file_path).first.slice(/[^\t]*/).strip

  size_duration_ratio = size_machine / duration_machine

  url = Open3.capture2('mdls', '-raw', '-name', 'kMDItemWhereFroms', file_path).first.split("\n")[1].strip.delete('"') rescue nil

  hash = {
    'id' => id,
    'type' => 'file',
    'name' => name,
    'path' => file_path,
    'count' => nil,
    'url' => url,
    'duration' => {
      'machine' => duration_machine,
      'human' => duration_human
    },
    'size' => {
      'machine' => size_machine,
      'human' => size_human
    },
    'ratio' => size_duration_ratio
  }

  add_to_list(hash, 'towatch')
end

def add_dir_to_watchlist(dir_path, id = random_hex)
  name = File.basename(dir_path)

  hash = {
    'id' => id,
    'type' => 'series',
    'name' => name,
    'path' => dir_path,
    'count' => 'counting files…',
    'url' => nil,
    'duration' => {
      'machine' => nil,
      'human' => 'getting duration…'
    },
    'size' => {
      'machine' => nil,
      'human' => 'calculating size…'
    },
    'ratio' => nil
  }

  add_to_list(hash, 'towatch')
  update_series(id)
end

def update_series(id)
  all_lists = read_lists
  item_index = find_index(id, 'towatch', all_lists)
  item = all_lists['towatch'][item_index]

  dir_path = item['path']
  audiovisual_files = list_audiovisual_files(dir_path)
  first_file = audiovisual_files.first
  count = audiovisual_files.count

  duration_machine = duration_in_seconds(first_file)
  duration_human = seconds_to_hms(duration_machine)

  size_machine = Open3.capture2('du', first_file).first.to_i
  size_human = Open3.capture2('du', '-h', first_file).first.slice(/[^\t]*/).strip

  size_duration_ratio = size_machine / duration_machine

  item['count'] = count
  item['duration']['machine'] = duration_machine
  item['duration']['human'] = duration_human
  item['size']['machine'] = size_machine
  item['size']['human'] = size_human
  item['ratio'] = size_duration_ratio

  write_lists(all_lists)
end

def add_url_to_watchlist(url, playlist = false, id = random_hex)
  playlist_flag = playlist ? '--yes-playlist' : '--no-playlist'

  all_names = Open3.capture2('yt-dlp', '--print', 'title', playlist_flag, url).first.split("\n")
  error "Could not add url as stream: #{url}" if all_names.empty?
  # If playlist, get the playlist name instead of the the name of the first item
  name = all_names.count > 1 ? Open3.capture2('yt-dlp', '--yes-playlist', '--print', 'filename', '--output', '%(playlist)s', url).first.split("\n").first : all_names[0]

  durations = Open3.capture2('yt-dlp', '--print', 'duration', playlist_flag, url).first.split("\n")
  count = durations.count > 1 ? durations.count : nil

  duration_machine = durations.map { |d| colons_to_seconds(d) }.inject(0, :+)
  duration_human = seconds_to_hms(duration_machine)

  hash = {
    'id' => id,
    'type' => 'stream',
    'name' => name,
    'path' => nil,
    'count' => count,
    'url' => url,
    'duration' => {
      'machine' => duration_machine,
      'human' => duration_human
    },
    'size' => {
      'machine' => nil,
      'human' => nil
    },
    'ratio' => nil
  }

  add_to_list(hash, 'towatch')
  notification("Added as stream: “#{name}”")
end

def display_towatch(sort = nil)
  item_list = read_lists['towatch']

  if item_list.empty?
    puts({ items: [{ title: 'Play (wlp)', subtitle: 'Nothing to watch', valid: false }] }.to_json)
    exit 0
  end

  script_filter_items = []

  hash_to_output =
    case sort
    when 'duration_ascending'
      item_list.sort_by { |content| content['duration']['machine'] }
    when 'duration_descending'
      item_list.sort_by { |content| content['duration']['machine'] }.reverse
    when 'size_ascending'
      item_list.sort_by { |content| content['size']['machine'] || Float::INFINITY }
    when 'size_descending'
      item_list.sort_by { |content| content['size']['machine'] || -Float::INFINITY }.reverse
    when 'best_ratio'
      item_list.sort_by { |content| content['ratio'] || -Float::INFINITY }.reverse
    else
      item_list
    end

  hash_to_output.each do |details|
    item_count = details['count'].nil? ? '' : "(#{details['count']}) 𐄁 "

    # Common values
    item = {
      title: details['name'],
      arg: details['id'],
      mods: {},
      action: {}
    }

    # Common modifications
    case details['type']
    when 'file', 'series' # Not a stream
      item[:subtitle] = "#{item_count}#{details['duration']['human']} 𐄁 #{details['size']['human']} 𐄁 #{details['path']}"
    end

    item[:mods][:ctrl] = details['url'].nil? ? { subtitle: 'This item has no origin url', valid: false } : { subtitle: details['url'], arg: details['url'] }

    # Specific modifications
    case details['type']
    when 'file'
      item[:quicklookurl] = details['path']
      item[:mods][:alt] = { subtitle: 'This modifier is only available on series and streams', valid: false }
      item[:action][:auto] = Prefer_action_url && !details['url'].nil? ? details['url'] : details['path']
    when 'stream'
      item[:subtitle] = "≈ #{item_count}#{details['duration']['human']} 𐄁 #{details['url']}"
      item[:quicklookurl] = details['url']
      item[:mods][:alt] = { subtitle: 'Download stream' }
      item[:action][:url] = details['url']
    when 'series'
      item[:mods][:alt] = { subtitle: 'Rescan series' }
      item[:action][:file] = details['path']
    end

    script_filter_items.push(item)
  end

  puts({ items: script_filter_items }.to_json)
end

def display_watched
  item_list = read_lists['watched']

  if item_list.empty?
    puts({ items: [{ title: 'Mark unwatched (wlu)', subtitle: 'You have no unwatched files', valid: false }] }.to_json)
    exit 0
  end

  script_filter_items = []

  item_list.each do |details|
    # Common values
    item = {
      title: details['name'],
      arg: details['id'],
      mods: {},
      action: {}
    }

    # Modifications
    if details['url'].nil?
      item[:subtitle] = details['path']
      item[:mods][:ctrl] = { subtitle: 'This item has no origin url', valid: false }
      item[:mods][:alt] = { subtitle: 'This item has no origin url', valid: false }
    else
      item[:subtitle] = details['type'] == 'stream' ? details['url'] : "#{details['url']} 𐄁 #{details['path']}"
      item[:quicklookurl] = details['url']
      item[:mods][:ctrl] = { subtitle: 'Open link in default browser', arg: details['url'] }
      item[:mods][:alt] = { subtitle: 'Copy link to clipboard', arg: details['url'] }
      item[:action][:url] = details['url']
    end

    script_filter_items.push(item)
  end

  puts({ items: script_filter_items }.to_json)
end

def play(id)
  switch_list(id, 'towatch', 'towatch') if Top_on_play

  all_lists = read_lists
  item_index = find_index(id, 'towatch', all_lists)
  item = all_lists['towatch'][item_index]

  case item['type']
  when 'file'
    return unless play_item('file', item['path'])

    mark_watched(id)
  when 'stream'
    return unless play_item('stream', item['url'])

    mark_watched(id)
  when 'series'
    unless File.exist?(item['path'])
      mark_watched(id)
      abort 'Marking as watched since the directory no longer exists'
    end

    first_file = list_audiovisual_files(item['path']).first
    return unless play_item('file', first_file)

    # If there are no more audiovisual files in the directory in addition to the one we just watched, trash the whole directory, else trash just the watched file
    if list_audiovisual_files(item['path']).reject { |e| e == first_file }.empty?
      mark_watched(id)
    else
      trash(first_file) if Trash_on_watched
      update_series(id)
    end
  end
end

# By checking for and running the CLI of certain players instead of the app bundle, we get access to the exit status. That way, in the 'play' method, even if the file were to be marked as watched we do not do it unless it was a success.
# This means we can configure our video player to not exit successfully on certain conditions and have greater granularity with WatchList.
def play_item(type, path)
  return true if path.nil? || type != 'stream' && !File.exist?(path) # If non-stream item does not exist, exit successfully so it can still be marked as watched

  # The 'split' together with 'last' serves to try to pick the last installed version, in case more than one is found (multiple versions in Homebrew Cellar, for example)
  video_player = lambda {
    mpv_homebrew_apple_silicon = '/opt/homebrew/bin/mpv'
    return [mpv_homebrew_apple_silicon, '--no-terminal'] if File.executable?(mpv_homebrew_apple_silicon)

    mpv_homebrew_intel = '/usr/local/bin/mpv'
    return [mpv_homebrew_intel, '--no-terminal'] if File.executable?(mpv_homebrew_intel)

    mpv_app = Open3.capture2('mdfind', 'kMDItemCFBundleIdentifier', '=', 'io.mpv').first.strip.split("\n").last
    return [mpv_app + '/Contents/MacOS/mpv', '--no-terminal'] if mpv_app

    iina = Open3.capture2('mdfind', 'kMDItemCFBundleIdentifier', '=', 'com.colliderli.iina').first.strip.split("\n").last
    return iina + '/Contents/MacOS/IINA' if iina

    vlc = Open3.capture2('mdfind', 'kMDItemCFBundleIdentifier', '=', 'org.videolan.vlc').first.strip.split("\n").last
    return vlc + '/Contents/MacOS/VLC' if vlc

    'other'
  }.call

  error('To play a stream you need mpv, iina, or vlc') if video_player == 'other' && type == 'stream'

  video_player == 'other' ? system('open', '-W', path) : Open3.capture2(*video_player, path)[1].success?
end

def mark_watched(id)
  switch_list(id, 'towatch', 'watched')

  all_lists = read_lists
  item_index = find_index(id, 'watched', all_lists)
  item = all_lists['watched'][item_index]

  all_lists['watched'] = all_lists['watched'].first(Maximum_watched)
  write_lists(all_lists)

  if item['type'] == 'stream'
    system('/usr/bin/afplay', '/System/Library/Sounds/Purr.aiff')
    return
  end

  # Trash
  return unless Trash_on_watched

  trashed_name = trash(item['path'])
  return if File.basename(item['path']) == trashed_name

  # If name had to change to send to Trash, update list with new name
  item['trashed_name'] = trashed_name
  write_lists(all_lists)
end

def mark_unwatched(id)
  switch_list(id, 'watched', 'towatch')

  # Try to recover trashed file
  return unless Trash_on_watched

  all_lists = read_lists
  item_index = find_index(id, 'towatch', all_lists)
  item = all_lists['towatch'][item_index]

  return if item['type'] == 'stream'

  if item['trashed_name']
    trashed_path = File.join(ENV['HOME'], '.Trash', item['trashed_name'])
    item.delete('trashed_name')
    write_lists(all_lists)
  else
    trashed_path = File.join(ENV['HOME'], '.Trash', File.basename(item['path']))
  end

  error('Could not find item in Trash') unless File.exist?(trashed_path)
  error('Could not recover from Trash because another item exists at original location') if File.exist?(item['path'])

  File.rename(trashed_path, item['path'])
  system('/usr/bin/afplay', '/System/Library/Sounds/Submarine.aiff')
end

def download_stream(id)
  all_lists = read_lists
  item_index = find_index(id, 'towatch', all_lists)
  item = all_lists['towatch'][item_index]
  url = item['url']

  mark_watched(id)
  puts url
end

def read_towatch_order
  print read_lists['towatch'].map { |item| "#{item['id']}: #{item['name']}" }.join("\n")
end

def write_towatch_order(text_order)
  all_lists = read_lists

  new_items = text_order.strip.split("\n").each_with_object([]) { |item, new_array|
    id_name = item.split(':')
    id = id_name[0].strip
    name = id_name[1..-1].join(':').strip

    item_index = find_index(id, 'towatch', all_lists)
    item = all_lists['towatch'][item_index]

    abort "Unrecognised id: #{id}" if item_index.nil?
    item['name'] = name

    new_array.push(item)
  }

  all_lists['towatch'] = new_items
  write_lists(all_lists)
end

def verify_quick_playlist(minutes_threshold = 3)
  return false unless File.exist?(Quick_playlist)

  if (Time.now - File.mtime(Quick_playlist)) / 60 > minutes_threshold
    File.delete(Quick_playlist)
    return false
  end

  true
end

def add_to_quick_playlist(id)
  verify_quick_playlist
  File.write(Quick_playlist, "#{id}\n", mode: 'a')
end

def play_quick_playlist
  return false unless verify_quick_playlist

  ids = File.readlines(Quick_playlist, chomp: true)
  File.delete(Quick_playlist)

  ids.each do |id|
    system('osascript', '-l', 'JavaScript', '-e', "Application('com.runningwithcrayons.Alfred').runTrigger('play_id', { inWorkflow: 'com.vitorgalvao.alfred.watchlist', withArgument: '#{id}' })")
  end
end

def random_hex
  require 'securerandom'
  SecureRandom.hex(6)
end

def colons_to_seconds(duration_colons)
  duration_colons.split(':').map(&:to_i).inject(0) { |a, b| a * 60 + b }
end

def duration_in_seconds(file_path)
  Open3.capture2('ffprobe', '-loglevel', 'quiet', '-output_format', 'csv=p=0', '-show_entries', 'format=duration', file_path).first.to_i
end

def seconds_to_hms(total_seconds)
  return '[Unable to Get Duration]' if total_seconds.zero? # Can happen with yt-dlp's generic extractor (e.g. when adding direct link to an MP4)

  seconds = total_seconds % 60
  minutes = (total_seconds / 60) % 60
  hours = total_seconds / (60 * 60)

  duration_array = [hours, minutes, seconds]
  duration_array.shift while duration_array[0].zero? # Remove leading '0' time segments
  duration_array.join(':').sub(/$/, 's').sub(/(.*):/, '\1m ').sub(/(.*):/, '\1h ')
end

def audiovisual_file?(path)
  Open3.capture2('mdls', '-name', 'kMDItemContentTypeTree', path).first.include?('public.audiovisual-content')
end

def list_audiovisual_files(dir_path)
  escaped_path = dir_path.gsub(/([\*\?\[\]{}\\])/, '\\\\\1')
  Dir.glob("#{escaped_path}/**/*").map(&:downcase).sort.select { |e| audiovisual_file?(e) }
end

def require_audiovisual(path)
  if File.file?(path)
    return if audiovisual_file?(path)

    error('Is not an audiovisual file')
  elsif File.directory?(path)
    return unless list_audiovisual_files(path).first.nil?

    error('Directory has no audiovisual content')
  else
    error('Not a valid path')
  end
end

def read_lists(lists_file = Lists_file)
  JSON.parse(File.read(lists_file))
end

def write_lists(new_lists, lists_file = Lists_file)
  File.write(lists_file, JSON.pretty_generate(new_lists))
end

def add_to_list(new_hash, list, prepending = Prepend_new)
  all_lists = read_lists
  all_lists[list] = prepending ? [new_hash].concat(all_lists[list]) : all_lists[list].concat([new_hash])
  write_lists(all_lists)
end

def find_index(id, list, all_lists)
  all_lists[list].index { |item| item['id'] == id }
end

def delete_from_list(id, list)
  all_lists = read_lists
  item_index = find_index(id, list, all_lists)
  item = all_lists[list][item_index]
  all_lists[list].delete(item)
  write_lists(all_lists)
end

def switch_list(id, origin_list, target_list)
  all_lists = read_lists
  item_index = find_index(id, origin_list, all_lists)

  abort 'Item no longer exists' if item_index.nil? # Detect if an item no longer exists before trying to move. Fix for cases where the same item is chosen a second time before having finished playing.

  item = all_lists[origin_list][item_index]
  delete_from_list(id, origin_list)
  add_to_list(item, target_list, true)
end

def trash(path)
  Open3.capture2('osascript', '-l', 'JavaScript', '-e', 'function run(argv) { return Application("Finder").delete(Path(argv[0])).name() }', path).first.strip if File.exist?(path)
end

def notification(message, sound = '')
  system("#{Dir.pwd}/notificator", '--message', message, '--title', ENV['alfred_workflow_name'], '--sound', sound)
end

def error(message)
  notification(message, 'Sosumi')
  abort(message)
end
