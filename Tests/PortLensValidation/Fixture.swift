import Foundation

extension CoreValidation {
    static let fixture = #"""
    {
      "SPUSBDataType": [
        {
          "_name": "USB31Bus", "host_controller": "ExampleController",
          "_items": [
            {
              "_name": "USB 2.0 Hub     ", "manufacturer": " Example Vendor ",
              "location_id": "0x00100000 / 1", "vendor_id": "0x1234 (Example)", "product_id": "0x0001",
              "device_speed": "high_speed", "serial_num": "SECRET_SERIAL", "unexpected": "SECRET_EXTRA",
              "_items": [
                {
                  "_name": "iLok", "location_id": "0x00110000 / 2",
                  "vendor_id": "0x088e", "product_id": "0x5036", "device_speed": "full_speed"
                },
                {
                  "_name": "hub_device", "location_id": "0x00120000 / 3",
                  "_items": [
                    { "_name": "iLok", "location_id": "0x00121000 / 4", "vendor_id": "0x088e", "product_id": "0x5036" }
                  ]
                }
              ]
            }
          ]
        },
        { "_name": "USB31Bus", "host_controller": "ExampleController" }
      ],
      "SPThunderboltDataType": [
        {
          "_name": "thunderboltusb4_bus_0", "domain_uuid_key": "SECRET_DOMAIN_UUID",
          "_items": [
            {
              "_name": "Example Dock", "vendor_name_key": "Example", "route_string_key": "1",
              "vendor_id_key": "0x12", "device_id_key": "0x34", "mode_key": "usb_four",
              "switch_uid_key": "SECRET_SWITCH_UID", "mac_address": "SECRET_MAC",
              "receptacle_upstream_ambiguous_tag": {
                "current_speed_key": "Up to 40 Gb/s x1", "cm_asn_key": "SECRET_CABLE_SERIAL"
              },
              "_items": [
                { "_name": "Example Display", "route_string_key": "101", "vendor_id_key": "0x56", "device_id_key": "0x78" }
              ]
            }
          ]
        },
        { "_name": "thunderboltusb4_bus_1" }
      ]
    }
    """#
}
