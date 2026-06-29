from PIL import Image
img = Image.open('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png')
img.save('windows/runner/resources/app_icon.ico', format='ICO', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
print("ICO done!")
