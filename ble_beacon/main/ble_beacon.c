#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "nvs.h"
#include "nvs_flash.h"
#include "esp_log.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"

#define NVS_NAMESPACE "beacon"
#define KEY_DEVICE_ID "id"

static const char *TAG = "BEACON";

/* -------- Device ID -------- */
static uint16_t device_id = 1;

/* -------- Payload v1 --------
 Byte Layout:
 [0] 0xFF  - Company ID LSB  (reserved/prototype)
 [1] 0xFF  - Company ID MSB  (reserved/prototype)
 [2] 0x01  - Version
 [3] 0x01  - Device Type     (0x01 = patient beacon)
 [4]       - ID MSB
 [5]       - ID LSB
 [6] 0x00  - Flags
 [7] 0xFF  - Battery         (TODO: Replace with actual ADC battery reading)
*/
static uint8_t payload[8] = {
    0xFF,   /* Company ID LSB */
    0xFF,   /* Company ID MSB */
    0x01,   /* Version        */
    0x01,   /* Device Type    */
    0x00,   /* ID MSB         */
    0x01,   /* ID LSB         */
    0x00,   /* Flags          */
    0xFF    /* Battery        */
};

/* ================= NVS ================= */
static void load_device_id(void)
{
    nvs_handle_t handle;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &handle) == ESP_OK) {
        uint16_t id;
        if (nvs_get_u16(handle, KEY_DEVICE_ID, &id) == ESP_OK) {
            device_id = id;
        }
        nvs_close(handle);
    }
}

static void save_device_id(uint16_t id)
{
    nvs_handle_t handle;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &handle) == ESP_OK) {
        nvs_set_u16(handle, KEY_DEVICE_ID, id);
        nvs_commit(handle);
        nvs_close(handle);
    }
}

/* ================= BLE ================= */
static void advertise(void)
{
    struct ble_gap_adv_params adv_params;
    struct ble_hs_adv_fields fields;

    memset(&fields, 0, sizeof(fields));
    fields.flags = BLE_HS_ADV_F_DISC_GEN |
                   BLE_HS_ADV_F_BREDR_UNSUP;
    fields.mfg_data     = payload;
    fields.mfg_data_len = sizeof(payload);
    ble_gap_adv_set_fields(&fields);

    memset(&adv_params, 0, sizeof(adv_params));
    adv_params.conn_mode = BLE_GAP_CONN_MODE_NON;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    adv_params.itvl_min  = BLE_GAP_ADV_ITVL_MS(300);
    adv_params.itvl_max  = BLE_GAP_ADV_ITVL_MS(500);

    ble_gap_adv_start(
        BLE_OWN_ADDR_PUBLIC,
        NULL,
        BLE_HS_FOREVER,
        &adv_params,
        NULL,
        NULL);
}

static void on_sync(void)
{
    ESP_LOGI(TAG, "BLE Stack Synced");

    /* Insert device ID into payload before advertising */
    payload[4] = (device_id >> 8) & 0xFF;
    payload[5] = device_id & 0xFF;

    ESP_LOGI(TAG, "Device ID: %u (0x%02X 0x%02X)", device_id, payload[4], payload[5]);

    advertise();
}

void host_task(void *param)
{
    nimble_port_run();
    nimble_port_freertos_deinit();
}

/* ================= APP ================= */
void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    /* Load stored device ID from NVS */
    load_device_id();
    ESP_LOGI(TAG, "Loaded Device ID: %u", device_id);

    ESP_LOGI(TAG, "Starting NimBLE Beacon");
    nimble_port_init();
    ble_hs_cfg.sync_cb = on_sync;
    nimble_port_freertos_init(host_task);
}