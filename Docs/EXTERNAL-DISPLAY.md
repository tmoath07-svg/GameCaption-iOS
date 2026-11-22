# External subtitle display

## Browser on a second display

1. Run GameCaption on iPhone and connect iPhone and the browser device to the same Wi-Fi network. Allow GameCaption access to the local network if prompted.
2. Start the camera and point it at the game screen. Adjust the OCR region, then open the subtitle sharing panel and start sharing.
3. Open the browser URL shown in GameCaption on a TV browser, tablet, computer or second phone. Keep GameCaption in the foreground. Return from the sharing panel to watch the camera preview if needed.
4. Keep the console on its normal TV input. A second screen can display subtitles alongside the game. A TV with multi-view may be able to show its browser next to HDMI, depending on the TV model and the inputs it supports.

The browser needs local HTTP, JavaScript and access to the iPhone's IPv4 Wi-Fi address. Guest networks that isolate clients prevent the connection. Share the URL only with viewers on your network. It grants access to the currently displayed text until sharing stops. A new sharing session creates a fresh URL.

## HDMI compositor using OBS

Use a computer running OBS, an HDMI capture device that supports the console's output format, and a display connected to the computer. Connect the supported console output to the capture device and add it as a Video Capture Device in OBS. Position the iPhone to read the TV or the capture device's passthrough display. In GameCaption, copy the transparent OBS URL. Add it as a Browser Source above the video source and set its width and height to match the OBS canvas. Display the composite using OBS's fullscreen projector. The browser source shows the caption over the captured video and becomes transparent when the subtitle clears. In fullscreen projection, use the native HDMI display or passthrough for direct gameplay when capture latency affects controls. [OBS browser source](https://obsproject.com/kb/browser-source)

This setup requires video that the capture device is permitted to receive. The iPhone cannot insert graphics into another device's independent HDMI signal. The LAN server is foreground-only. Use the camera for continuous TV display while the console plays independently, since switching iPhone to another app suspends or stops the host server. On hardware, test the TV browser, HDMI capture and OBS output together.
