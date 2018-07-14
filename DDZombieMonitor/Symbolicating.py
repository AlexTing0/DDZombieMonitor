#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import re
import sys

def symbolicating(architecture,executable,loadAddress,funAddress,uuid):
    cmd = 'atos -arch ' + architecture + ' -o ' + executable + ' -l ' + loadAddress + ' ' + funAddress
    if os.path.isfile(executable.replace('\\','')) == False:
        print executable, 'is not exist!'
        return None
    uuid_cmd = 'dwarfdump -arch ' + architecture + ' -u ' + executable
    executable_uuid_full = os.popen(uuid_cmd).read()
    uuid_re = re.compile('UUID: ([^-]*)-([^-]*)-([^-]*)-([^-]*)-([^- ]*) \(.*')
    executable_uuid = ''
    uuid_re_match = uuid_re.match(executable_uuid_full)
    if uuid_re_match is not None:
        if '-' in uuid:
            executable_uuid = uuid_re_match.groups()[0] + '-' + uuid_re_match.groups()[1] + '-' + \
                              uuid_re_match.groups()[2] + '-' + uuid_re_match.groups()[3] + '-' + \
                              uuid_re_match.groups()[4]
        else:
            executable_uuid = uuid_re_match.groups()[0] + uuid_re_match.groups()[1] + \
                              uuid_re_match.groups()[2] + uuid_re_match.groups()[3] + \
                              uuid_re_match.groups()[4]
    executable_uuid_lower = executable_uuid.lower()
    uuid_lower = uuid.lower()
    if uuid_lower != executable_uuid_lower:
        print 'uuid: ' + uuid +' is not match executable uuid: '\
            ,executable_uuid_lower,'executable_uuid_full',executable_uuid_full
        return None
    print 'symbolicating',cmd,'...'
    symbol = os.popen(cmd).read()
    return symbol

'''
image item:[loadAddress, endAddress, imageName, architecture, uuid, directory, long(loadAddress), long(endAddress)]
'''
def parseBinaryImages(crashLog):
    print 'parseBinaryImages: ',crashLog
    crash_log = open(crashLog)
    images_dict = {}
    image_begin = False
    # image_re like loadAddress - endAddress imageName architecture <uuid> directory
    image_re = re.compile('[^0]*(0x[^ ]*) - ([^ ]*) (.*) ([^ ]*) <([^>]*)> ([^ \r\n]*).*')
    for line in crash_log :
        if 'OS Version:' in line:
            version_re = re.compile('OS Version:\D*([\d].*) \(([^ ][^\)]*)\).*')
            version = version_re.match(line)
            images_dict['OS Version']=version.groups()[0] + ' (' + version.groups()[1] + ')'
        else:
            modules = image_re.match(line)
            if modules is not None:
                image_info = [modules.groups()[0], modules.groups()[1], modules.groups()[2], modules.groups()[3],modules.groups()[4], modules.groups()[5], long(modules.groups()[0],0),long(modules.groups()[1],0)]
                images_dict[modules.groups()[2]] = image_info
    crash_log.close()
    return  images_dict

def imageForAddress(images, address):
    for image in images.values():
        if long(address, 0) > image[6] and long(address, 0) < image[7]:
            return image
    return None

def symbolStack(images, sym_path, system_symbol_base_dir, line):
    symbol_str = ''
    stack_re = re.compile('stack:\[([^\]]*).*')
    stack = stack_re.match(line)
    if stack is None:
        return ''
    address_list = stack.groups()[0].split(',')
    index = 0
    for address in address_list:
        if len(address) > 0:
            image = imageForAddress(images, address)
            if image:
                symbol = image[0] + ' + ' + str(long(address, 0)-image[6])
                image_name = image[2]
                image_path = ''
                if image_name == 'Demo':
                    image_path = sym_path
                else:
                    image_path = system_symbol_base_dir + image[5]
                symbolicating_re = symbolicating(image[3], image_path, image[0], address, image[4])
                if symbolicating_re is not None:
                    symbol = symbolicating_re
                symbol_str += str(index).ljust(5) + image[2].ljust(30) + address + ' ' +symbol+'\r\n'
            else:
                symbol_str += str(index).ljust(5) + address + '\r\n'
            index += 1
    return symbol_str

def formatZombieInfo(base_path):
    print base_path
    sym_path = base_path + '/Demo.app.dSYM/Contents/Resources/DWARF/Demo'
    attach_log = open(base_path + '/crash_attach.log')
    zombie_info = open(base_path + '/zombie_info.log','w')
    zombie_info_str = 'Zombie Info\r\n\r\n'
    image_info = parseBinaryImages(base_path + '/crash_attach.log')
    if image_info is None:
        return
    version = image_info['OS Version']
    version_re = re.compile('([^ ]*) \(([^\)]*)\)')
    version_re_match = version_re.match(version)
    if version_re_match is not None:
        version = version_re_match.groups()[0] + '\ \(' + version_re_match.groups()[1] + '\)'
    system_symbol_base_dir =  os.environ['HOME'] + '/Library/Developer/Xcode/iOS\ DeviceSupport/' + version + '/Symbols'
    call_stack_begin = False
    dealloc_stack_begin = False
    frame_begin = False
    #frame_re like             num       imageName  address fun
    frame_re = re.compile('[\D]*([\d]+)( *)([^ ]+)( *)([^ ]+) *([^ ][^\r\n]+).*')
    for line in attach_log:
        if 'zombie stack:' in line:
            call_stack_begin = True
            zombie_info_str += 'Zombie Call Stack:\r\n'
        elif 'dealloc stack:' in line:
            call_stack_begin = False
            dealloc_stack_begin = True
            zombie_info_str += '\r\nDealloc Stack:\r\n'
        elif 'ZombieInfo' in line:
            zombie_re = re.compile('.*class:([^ ]*) obj:([^ ]*) sel:([^ \r\n]*).*')
            zombie = zombie_re.match(line)
            if zombie is not None:
                zombie_info_str += 'Zombie Class Name: '+zombie.groups()[0]+'\r\nZombie Object Address: '+\
                                   zombie.groups()[1]+'\r\nSelector Name: '+zombie.groups()[2]+'\r\n\r\n'
        elif call_stack_begin:
            if 'tid' in line:
                zombie_info_str += line
            elif 'stack' in line:
                zombie_info_str += symbolStack(image_info, sym_path, system_symbol_base_dir, line)
                call_stack_begin = False
                break
        elif dealloc_stack_begin:
            if 'tid' in line:
                zombie_info_str += line
            elif 'stack' in line:
                zombie_info_str += symbolStack(image_info, sym_path, system_symbol_base_dir, line)
                dealloc_stack_begin = False
    zombie_info.write(zombie_info_str)
    zombie_info.close()
    attach_log.close()


'''
if __name__ == '__main__':
    formatZombieInfo('/Users/haishengding/Desktop/github/DDZombieMonitor/crash')
'''


'''
脚本使用方法
1.把crash_attach.log和Demo.app.dSYM放在一个目录，替换脚本中Demo为自己对工程名
2.把目录DIR传给脚本，符号化完成后在该目录生成zombie_info.log文件
e.g
python Symbolicating_Zombie.py '/Users/huya/Documents/work/zombie/crash'
'''

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print "please input corrent arg!"
    formatZombieInfo(sys.argv[1])
