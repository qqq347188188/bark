# frozen_string_literal: true

# 在 CI（macOS runner）中把本次新增的源文件加入 Xcode 工程对应 target，
# 并为 NotificationServiceExtension 链接系统 Photos.framework（自动保存相册所需）。
# 使用者无需本地 Xcode，全部由 CI 自动完成。
require 'xcodeproj'

PROJECT = 'Bark.xcodeproj'
project = Xcodeproj::Project.open(PROJECT)

# target 名称 => 需要加入的工程相对路径文件列表
files_by_target = {
  'Bark' => [
    'Model/DeliveryReceipt.swift',
    'Controller/DeliverySettingManager.swift',
    'Controller/DeliveryManager.swift',
    'Common/PushImageSettingManager.swift'
  ],
  'NotificationServiceExtension' => [
    'Common/PushImageSettingManager.swift',
    'NotificationServiceExtension/PhotoAlbumSaver.swift',
    'NotificationServiceExtension/Processor/DeliveryProcessor.swift'
  ]
}

files_by_target.each do |target_name, files|
  target = project.targets.find { |t| t.name == target_name }
  abort "找不到 target: #{target_name}" unless target

  files.each do |file_path|
    parts = file_path.split('/')
    file_name = parts.pop
    current = project.main_group
    parts.each do |part|
      child = current.children.find { |c| c.display_name == part } || current.new_group(part)
      current = child
    end

    # group 内的文件引用在两个 target 间共享，仅在不存在时创建
    existing = current.files.find { |f| f.path == file_name }
    file_ref = existing || current.new_file(file_name)

    # 仅当本 target 的编译源中尚未包含该文件时才添加（避免重复加入多个 target 时漏加）
    already = target.source_build_phase.files.any? { |bf| bf.file_ref == file_ref }
    next if already

    target.source_build_phase.add_file_reference(file_ref)
    puts "已添加 #{file_path} -> #{target_name}"
  end
end

# 为 NotificationServiceExtension 链接系统 Photos.framework
ext = project.targets.find { |t| t.name == 'NotificationServiceExtension' }
frameworks = project.frameworks_group
unless ext.frameworks_build_phase.files.any? { |f| f.display_name == 'Photos.framework' }
  photos = frameworks.new_file('Photos.framework')
  photos.source_tree = 'SDKROOT'
  photos.set_path('System/Library/Frameworks/Photos.framework')
  ext.frameworks_build_phase.add_file_reference(photos)
  puts '已为 NotificationServiceExtension 链接 Photos.framework'
end

project.save
puts 'xcodeproj 更新完成'
