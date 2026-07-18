#!/usr/bin/env bash
# Quick frame sanity check for a Blackfly GigE camera (uses Spinnaker SDK).
#
#   ~/used\ for\ ROAM/scripts/diagnose_blackfly_cam.sh cam1
#   ~/used\ for\ ROAM/scripts/diagnose_blackfly_cam.sh cam0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/blackfly_camera.conf"

WHICH="${1:-cam1}"
case "$WHICH" in
  cam0|0) SERIAL="13125051" ;;
  cam1|1) SERIAL="13294999" ;;
  *) echo "Usage: $0 [cam0|cam1]" >&2; exit 1 ;;
esac

BIN=/tmp/spin_cam_test
if [[ ! -x "$BIN" ]]; then
  cat > /tmp/spin_cam_test.cpp <<'CPP'
#include "Spinnaker.h"
#include "SpinGenApi/SpinnakerGenApi.h"
#include <iostream>
using namespace Spinnaker; using namespace Spinnaker::GenApi; using namespace std;
static void setEnum(INodeMap& nm, const char* name, const char* value) {
  CEnumerationPtr node = nm.GetNode(name);
  if (!IsWritable(node)) return;
  CEnumEntryPtr entry = node->GetEntryByName(value);
  if (!IsReadable(entry)) return;
  node->SetIntValue(entry->GetValue());
}
static void setFloat(INodeMap& nm, const char* name, double value) {
  CFloatPtr node = nm.GetNode(name);
  if (!IsWritable(node)) return;
  node->SetValue(value);
}
static void dumpStats(const ImagePtr& img) {
  const unsigned char* data = static_cast<const unsigned char*>(img->GetData());
  size_t size = img->GetImageSize();
  unsigned char mn = 255, mx = 0;
  unsigned long long sum = 0;
  for (size_t j = 0; j < size; ++j) {
    mn = min<unsigned char>(mn, data[j]);
    mx = max<unsigned char>(mx, data[j]);
    sum += data[j];
  }
  cout << "live min=" << (int)mn << " max=" << (int)mx
       << " mean=" << (double)sum / size << endl;
}
int main(int argc, char** argv) {
  const char* target = argc > 1 ? argv[1] : "13294999";
  SystemPtr system = System::GetInstance();
  CameraList camList = system->GetCameras();
  for (unsigned int i = 0; i < camList.GetSize(); ++i) {
    CameraPtr cam = camList.GetByIndex(i);
    cam->Init();
    CStringPtr serial = cam->GetTLDeviceNodeMap().GetNode("DeviceSerialNumber");
    if (!IsReadable(serial) || string(serial->GetValue().c_str()) != target) {
      cam->DeInit();
      continue;
    }
    INodeMap& nm = cam->GetNodeMap();
    setEnum(nm, "PixelFormat", "Mono8");
    setEnum(nm, "TriggerMode", "Off");
    setEnum(nm, "ExposureMode", "Timed");
    setEnum(nm, "ExposureAuto", "Off");
    setFloat(nm, "ExposureTime", 10000.0);
    setEnum(nm, "GainAuto", "Off");
    setFloat(nm, "Gain", 0.0);
    cam->BeginAcquisition();
    ImagePtr live = cam->GetNextImage(2000);
    if (!live->IsIncomplete()) dumpStats(live);
    live->Release();
    setEnum(nm, "TestImageSelector", "TestImage1");
    ImagePtr test = cam->GetNextImage(2000);
    if (!test->IsIncomplete()) {
      cout << "test_pattern ";
      dumpStats(test);
    }
    test->Release();
    setEnum(nm, "TestImageSelector", "Off");
    cam->EndAcquisition();
    cam->DeInit();
    camList.Clear();
    system->ReleaseInstance();
    return 0;
  }
  camList.Clear();
  system->ReleaseInstance();
  return 2;
}
CPP
  g++ -o "$BIN" /tmp/spin_cam_test.cpp -I/opt/spinnaker/include -L/opt/spinnaker/lib \
    -lSpinnaker -Wl,-rpath,/opt/spinnaker/lib >/dev/null
fi

echo "=== Blackfly diagnose ($WHICH serial $SERIAL) ==="
arv-tool-0.8 2>/dev/null | grep "$SERIAL" || true
echo ""
"$BIN" "$SERIAL"
echo ""
echo "Interpretation:"
echo "  live mean ~255  + test_pattern mean ~127  => stream OK, live sensor saturated or faulty"
echo "  both ~255         => network/stream issue"
echo "  live mean < 50    => camera OK; retry preview"
