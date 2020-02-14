//
//  iosCopyShareExtension.js
//  This hook runs for the iOS platform when the plugin or platform is added.
//
// Source: https://github.com/DavidStrausz/cordova-plugin-today-widget
//

//
// The MIT License (MIT)
//
// Copyright (c) 2017 DavidStrausz
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

var fs = require('fs');
var path = require('path');
const PLUGIN_ID = "cordova-plugin-openwith-cxm";
const BUNDLE_SUFFIX = '.shareextension';
const IOS_URL_SCHEME = 'openwithcxm';
const IOS_UNIFORM_TYPE_IDENTIFIER = 'public.data';

function redError(message) {
    return new Error('"' + PLUGIN_ID + '" \x1b[1m\x1b[31m' + message + '\x1b[0m');
}


console.log('Copying "' + PLUGIN_ID + '/ShareExtension" to ios...');

// http://stackoverflow.com/a/26038979/5930772
function copyFileSync(source, target) {
  var targetFile = target;

  // If target is a directory a new file with the same name will be created
  if (fs.existsSync(target)) {
    if (fs.lstatSync(target).isDirectory()) {
      targetFile = path.join(target, path.basename(source));
    }
  }

  fs.writeFileSync(targetFile, fs.readFileSync(source));
}

function copyFolderRecursiveSync(source, target) {
  var files = [];

  // Check if folder needs to be created or integrated
  var targetFolder = path.join(target, path.basename(source));
  if (!fs.existsSync(targetFolder)) {
    fs.mkdirSync(targetFolder);
  }

  // Copy
  if (fs.lstatSync(source).isDirectory()) {
    files = fs.readdirSync(source);
    files.forEach(function(file) {
      var curSource = path.join(source, file);
      if (fs.lstatSync(curSource).isDirectory()) {
        copyFolderRecursiveSync(curSource, targetFolder);
      } else {
        copyFileSync(curSource, targetFolder);
      }
    });
  }
}

// Determine the full path to the app's xcode project file.
function findXCodeproject(context, callback) {
  var iosFolder = context.opts.cordova.project
    ? context.opts.cordova.project.root
    : path.join(context.opts.projectRoot, 'platforms/ios/');
  fs.readdir(iosFolder, function(err, data) {
    var projectFolder;
    var projectName;
    // Find the project folder by looking for *.xcodeproj
    if (data && data.length) {
      data.forEach(function(folder) {
        if (folder.match(/\.xcodeproj$/)) {
          projectFolder = path.join(iosFolder, folder);
          projectName = path.basename(folder, '.xcodeproj');
        }
      });
    }

    if (!projectFolder || !projectName) {
      throw redError('Could not find an .xcodeproj folder in: ' + iosFolder);
    }

    if (err) {
      throw redError(err);
    }

    callback(projectFolder, projectName);
  });
}


// Determine the full path to the ios platform
function iosFolder(context) {
  return context.opts.cordova.project
    ? context.opts.cordova.project.root
    : path.join(context.opts.projectRoot, 'platforms/ios/');
}

function replacePreferencesInFile(filePath, preferences) {
  var content = fs.readFileSync(filePath, 'utf8');
  for (var i = 0; i < preferences.length; i++) {
      var pref = preferences[i];
      var regexp = new RegExp(pref.key, "g");
      content = content.replace(regexp, pref.value);
  }
  fs.writeFileSync(filePath, content);
}

function forEachShareExtensionFile(context, callback) {
  var shareExtensionFolder = path.join(iosFolder(context), 'ShareExtension');
  fs.readdirSync(shareExtensionFolder).forEach(function(name) {
    // Ignore junk files like .DS_Store
    if (!/^\..*/.test(name)) {
      callback({
        name:name,
        path:path.join(shareExtensionFolder, name),
        extension:path.extname(name)
      });
    }
  });
}

function projectPlistPath(context, projectName) {
  return path.join(iosFolder(context), projectName, projectName + '-Info.plist');
}

function projectPlistJson(context, projectName) {
  var plist = require('plist');
  var path = projectPlistPath(context, projectName);
  return plist.parse(fs.readFileSync(path, 'utf8'));
}

function getPreferences(context, configXml, projectName) {
  var plist = projectPlistJson(context, projectName);

  var et = require('elementtree');
  var xmltree = et.parse(configXml);
  var bundleId = xmltree.getroot().attrib.id;

  var group = "group." + bundleId + BUNDLE_SUFFIX;
  return [{
    key: '__DISPLAY_NAME__',
    value: projectName
  }, {
    key: '__BUNDLE_IDENTIFIER__',
    value: '$(PRODUCT_BUNDLE_IDENTIFIER)'
  } ,{
      key: '__GROUP_IDENTIFIER__',
      value: group
  }, {
    key: '__BUNDLE_SHORT_VERSION_STRING__',
    value: plist.CFBundleShortVersionString
  }, {
    key: '__BUNDLE_VERSION__',
    value: plist.CFBundleVersion
  }, {
    key: '__URL_SCHEME__',
    value: IOS_URL_SCHEME
  }, {
    key: '__UNIFORM_TYPE_IDENTIFIER__',
    value: IOS_UNIFORM_TYPE_IDENTIFIER
  }];
}

// Return the list of files in the share extension project, organized by type
function getShareExtensionFiles(context) {
  var files = {source:[],plist:[],resource:[]};
  var FILE_TYPES = { '.h':'source', '.m':'source', '.plist':'plist' };
  forEachShareExtensionFile(context, function(file) {
    var fileType = FILE_TYPES[file.extension] || 'resource';
    files[fileType].push(file);
  });
  return files;
}

function printShareExtensionFiles(files) {
  console.log('    Found following files in your ShareExtension folder:');
  console.log('    Source files:');
  files.source.forEach(function(file) {
    console.log('     - ', file.name);
  });

  console.log('    Plist files:');
  files.plist.forEach(function(file) {
    console.log('     - ', file.name);
  });

  console.log('    Resource files:');
  files.resource.forEach(function(file) {
    console.log('     - ', file.name);
  });
}


module.exports = function(context) {
  var Q = require('q');
  var deferral = new Q.defer();

  findXCodeproject(context, function(projectFolder, projectName) {

    var srcFolder = path.join(context.opts.projectRoot, 'plugins', PLUGIN_ID, 'src', 'ios', 'ShareExtension');
    if (!fs.existsSync(srcFolder)) {
      throw redError('Missing extension project folder in ' + srcFolder + '.');
    }
    copyFolderRecursiveSync(srcFolder, path.join(context.opts.projectRoot, 'platforms', 'ios'));

    var configXml = fs.readFileSync(path.join(context.opts.projectRoot, 'config.xml'), 'utf-8');
    if (configXml) {
      configXml = configXml.substring(configXml.indexOf('<'));
    }

    var files = getShareExtensionFiles(context);
    printShareExtensionFiles(files);
debugger;
    var preferences = getPreferences(context, configXml, projectName);
    files.plist.concat(files.source).forEach(function(file) {
      replacePreferencesInFile(file.path, preferences);
      console.log('    Successfully updated ' + file.name);
    });


    deferral.resolve();
  });

  return deferral.promise;
};
