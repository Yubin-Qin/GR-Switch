#!/usr/bin/env python3
"""Generate an ordinary Xcode project, without XcodeGen or third-party dependencies."""
from pathlib import Path
import hashlib, json, plistlib, struct, zlib, math
ROOT = Path(__file__).resolve().parent.parent

def key(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def quote(s): return json.dumps(str(s))
objects = {}
folder_refs = {}
def add(label, value): objects[key(label)] = value; return key(label)
assets = ROOT / 'GRTransfer/Resources/Assets.xcassets'
(assets / 'AccentColor.colorset').mkdir(parents=True, exist_ok=True)
(assets / 'AppIcon.appiconset').mkdir(parents=True, exist_ok=True)
(assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
(assets / 'AccentColor.colorset/Contents.json').write_text(json.dumps({'colors': [{'idiom': 'universal','color': {'color-space':'srgb','components': {'red':'0.82','green':'0.19','blue':'0.16','alpha':'1.0'}}}], 'info': {'author':'xcode','version':1}}))
# A code-drawn aperture mark, not a raster photograph or third-party brand asset.
w = 1024; raw = bytearray()
for y in range(w):
    raw.append(0)
    for x in range(w):
        dx, dy = x-512, y-512; r = math.hypot(dx,dy)
        color = (23,25,28)
        if 250 < r < 276 or 168 < r < 181: color=(231,233,233)
        angle=math.atan2(dy,dx)
        if 183 < r < 249 and abs(((angle + r/500 + math.pi/6) % (math.pi/3))-math.pi/6) < .038: color=(231,233,233)
        if math.hypot(x-759,y-265)<29: color=(210,48,40)
        raw.extend(color)
def chunk(kind,data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
(assets/'AppIcon.appiconset/AppIcon.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,w,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
(assets/'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}))
info = {
 'CFBundleDisplayName':'GR Transfer','CFBundleName':'$(PRODUCT_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)',
 'CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundlePackageType':'APPL','CFBundleInfoDictionaryVersion':'6.0',
 'CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)',
 'LSRequiresIPhoneOS':True,'UILaunchScreen':{},
 'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},
 'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
 'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
 'NSBluetoothAlwaysUsageDescription':'用于发现并配对你的理光相机，读取相机 Wi-Fi 连接信息。',
 'NSLocalNetworkUsageDescription':'用于通过相机 Wi-Fi 浏览和下载原始 JPG 照片。',
 'NSPhotoLibraryUsageDescription':'用于选择和创建相簿、保存相机原片，并核对已导入照片以避免重复。',
 'NSPhotoLibraryAddUsageDescription':'用于将保留 EXIF 的相机原始 JPG 保存到系统照片图库。',
 'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},
}
(ROOT/'GRTransfer/Resources/Info.plist').write_bytes(plistlib.dumps(info,sort_keys=False))
(ROOT/'GRTransfer/Resources/GRTransfer.entitlements').write_bytes(plistlib.dumps({'com.apple.developer.networking.HotspotConfiguration':True}))
privacy={'NSPrivacyTracking':False,'NSPrivacyCollectedDataTypes':[], 'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults','NSPrivacyAccessedAPITypeReasons':['CA92.1']}]}
(ROOT/'GRTransfer/Resources/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacy))
source_builds=[]; resource_builds=[]; refs=[]
for path in sorted((ROOT/'GRTransfer').rglob('*.swift')):
    rel=str(path.relative_to(ROOT)); fid=add(rel, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = SOURCE_ROOT; }}')
    folder_refs.setdefault(str(path.parent.relative_to(ROOT)), []).append(fid); source_builds.append(add('build '+rel, f'{{isa = PBXBuildFile; fileRef = {fid}; }}'))
for rel,typ,build in [('GRTransfer/Resources/Assets.xcassets','folder.assetcatalog',True),('GRTransfer/Resources/PrivacyInfo.xcprivacy','text.xml',True),('GRTransfer/Resources/Info.plist','text.plist.xml',False),('GRTransfer/Resources/GRTransfer.entitlements','text.plist.entitlements',False)]:
    fid=add(rel,f'{{isa = PBXFileReference; lastKnownFileType = {typ}; path = {quote(rel)}; sourceTree = SOURCE_ROOT; }}'); folder_refs.setdefault('GRTransfer/Resources', []).append(fid)
    if build: resource_builds.append(add('build '+rel,f'{{isa = PBXBuildFile; fileRef = {fid}; }}'))
for folder, children in folder_refs.items():
    refs.append(add('group '+folder, f'{{isa = PBXGroup; name = {quote(folder)}; children = ({",".join(children)},); sourceTree = "<group>"; }}'))
config_refs = []
for filename in ['App.xcconfig', 'Signing.example.xcconfig']:
    rel = 'Config/' + filename
    config_refs.append(add(rel, f'{{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = {quote(rel)}; sourceTree = SOURCE_ROOT; }}'))
refs.append(add('group Config', f'{{isa = PBXGroup; name = Config; children = ({",".join(config_refs)},); sourceTree = "<group>"; }}'))
product=add('product','{isa = PBXFileReference; explicitFileType = wrapper.application; path = GRTransfer.app; sourceTree = BUILT_PRODUCTS_DIR; }')
products=add('products',f'{{isa = PBXGroup; name = Products; children = ({product},); sourceTree = "<group>"; }}')
main=add('main',f'{{isa = PBXGroup; children = ({",".join(refs+[products])},); sourceTree = "<group>"; }}')
sources=add('sources',f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(source_builds)},); runOnlyForDeploymentPostprocessing = 0; }}')
resources=add('resources',f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0; }}')
frameworks=add('frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }')
def config(label, settings):
    base = f'baseConfigurationReference = {key("Config/App.xcconfig")}; ' if label.startswith('target ') else ''
    return add(label, '{isa = XCBuildConfiguration; '+base+'name = '+label.split()[-1]+'; buildSettings = {'+''.join(f'{k} = {quote(v)};' for k,v in settings.items())+'}; }')
project_configs=[]; target_configs=[]
for mode in ['Debug','Release']:
    project_configs.append(config('project '+mode, {'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'26.6','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else ''}))
    target_configs.append(config('target '+mode, {'PRODUCT_NAME':'$(TARGET_NAME)','TARGETED_DEVICE_FAMILY':'1,2','INFOPLIST_FILE':'GRTransfer/Resources/Info.plist','CODE_SIGN_ENTITLEMENTS':'GRTransfer/Resources/GRTransfer.entitlements','CODE_SIGN_STYLE':'Automatic','MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','GENERATE_INFOPLIST_FILE':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SWIFT_EMIT_LOC_STRINGS':'YES'}))
for label,configs in [('project configs',project_configs),('target configs',target_configs)]:
    add(label,f'{{isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
target=add('target',f'{{isa = PBXNativeTarget; buildConfigurationList = {key("target configs")}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = GRTransfer; productName = GRTransfer; productReference = {product}; productType = "com.apple.product-type.application"; }}')
project=add('project',f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 26.0; SystemCapabilities = {{com.apple.HotspotConfiguration = {{enabled = 1; }}; }}; }}; }}; }}; buildConfigurationList = {key("project configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},); }}')
(ROOT/'GRTransfer.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(f'{k} = {v};\n' for k,v in objects.items())+f'}}; rootObject = {project}; }}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="GRTransfer.app" BlueprintName="GRTransfer" ReferencedContainer="container:GRTransfer.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="GRTransfer.app" BlueprintName="GRTransfer" ReferencedContainer="container:GRTransfer.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="GRTransfer.app" BlueprintName="GRTransfer" ReferencedContainer="container:GRTransfer.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(ROOT/'GRTransfer.xcodeproj/xcshareddata/xcschemes/GRTransfer.xcscheme').write_text(scheme)
print('Generated GRTransfer.xcodeproj')
