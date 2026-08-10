// Windows SDK x64 헤더와 관리형 interop 배치를 대조할 때만 수동으로 빌드하는 읽기 전용 probe입니다.
#include <winsock2.h>
#include <windows.h>
#include <fwpmu.h>
#include <netioapi.h>
#include <cstddef>
#include <iostream>
#include <cstdio>

#define OFFSET(native_type, native_field, managed_name) \
    std::cout << "\"" managed_name "\":" << offsetof(native_type, native_field)

template <typename T>
void begin_layout(const char* name) { std::cout << "\"" << name << "\":{\"size\":" << sizeof(T) << ",\"offsets\":{"; }
void end_layout(bool last = false) { std::cout << "}}" << (last ? "" : ","); }
void print_guid(const GUID& value)
{
    char buffer[37];
    std::snprintf(buffer, sizeof(buffer), "%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        value.Data1, value.Data2, value.Data3, value.Data4[0], value.Data4[1], value.Data4[2], value.Data4[3],
        value.Data4[4], value.Data4[5], value.Data4[6], value.Data4[7]);
    std::cout << buffer;
}

int main()
{
    std::cout << "{\"schemaVersion\":1,\"architecture\":\"x64\",\"layouts\":{";
    begin_layout<FWPM_PROVIDER_CONTEXT3>("FWPM_PROVIDER_CONTEXT3");
    OFFSET(FWPM_PROVIDER_CONTEXT3, providerContextKey, "ProviderContextKey"); std::cout << ',';
    OFFSET(FWPM_PROVIDER_CONTEXT3, displayData, "DisplayData"); std::cout << ',';
    OFFSET(FWPM_PROVIDER_CONTEXT3, flags, "Flags"); std::cout << ',';
    OFFSET(FWPM_PROVIDER_CONTEXT3, providerKey, "ProviderKey"); std::cout << ',';
    OFFSET(FWPM_PROVIDER_CONTEXT3, providerData, "ProviderData"); std::cout << ',';
    OFFSET(FWPM_PROVIDER_CONTEXT3, type, "Type"); std::cout << ',';
    OFFSET(FWPM_PROVIDER_CONTEXT3, networkConnectionPolicy, "NetworkConnectionPolicy"); std::cout << ',';
    OFFSET(FWPM_PROVIDER_CONTEXT3, providerContextId, "ProviderContextId"); end_layout();
    begin_layout<FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0>("FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0");
    OFFSET(FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0, numSettings, "Count"); std::cout << ','; OFFSET(FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0, settings, "Settings"); end_layout();
    begin_layout<FWPM_NETWORK_CONNECTION_POLICY_SETTING0>("FWPM_NETWORK_CONNECTION_POLICY_SETTING0");
    OFFSET(FWPM_NETWORK_CONNECTION_POLICY_SETTING0, type, "Type"); std::cout << ','; OFFSET(FWPM_NETWORK_CONNECTION_POLICY_SETTING0, value, "Value"); end_layout();
    begin_layout<FWPM_FILTER_CONDITION0>("FWPM_FILTER_CONDITION0");
    OFFSET(FWPM_FILTER_CONDITION0, fieldKey, "FieldKey"); std::cout << ','; OFFSET(FWPM_FILTER_CONDITION0, matchType, "MatchType"); std::cout << ','; OFFSET(FWPM_FILTER_CONDITION0, conditionValue, "ConditionValue"); end_layout();
    begin_layout<FWP_VALUE0>("FWP_VALUE0"); OFFSET(FWP_VALUE0, type, "Type"); std::cout << ','; OFFSET(FWP_VALUE0, uint64, "Value"); end_layout();
    begin_layout<FWP_CONDITION_VALUE0>("FWP_CONDITION_VALUE0"); OFFSET(FWP_CONDITION_VALUE0, type, "Type"); std::cout << ','; OFFSET(FWP_CONDITION_VALUE0, byteBlob, "Value"); end_layout();
    begin_layout<FWP_BYTE_BLOB>("FWP_BYTE_BLOB"); OFFSET(FWP_BYTE_BLOB, size, "Size"); std::cout << ','; OFFSET(FWP_BYTE_BLOB, data, "Data"); end_layout();
    begin_layout<FWPM_SESSION0>("FWPM_SESSION0");
    OFFSET(FWPM_SESSION0, sessionKey, "SessionKey"); std::cout << ','; OFFSET(FWPM_SESSION0, displayData, "DisplayData"); std::cout << ',';
    OFFSET(FWPM_SESSION0, flags, "Flags"); std::cout << ','; OFFSET(FWPM_SESSION0, txnWaitTimeoutInMSec, "TransactionWaitTimeoutMilliseconds"); std::cout << ',';
    OFFSET(FWPM_SESSION0, processId, "ProcessId"); std::cout << ','; OFFSET(FWPM_SESSION0, sid, "Sid"); std::cout << ',';
    OFFSET(FWPM_SESSION0, username, "Username"); std::cout << ','; OFFSET(FWPM_SESSION0, kernelMode, "KernelMode"); end_layout();
    begin_layout<NET_LUID>("NET_LUID"); end_layout(true);
    std::cout << "},\"constants\":{";
    std::cout << "\"NextHopInterface\":" << FWP_NETWORK_CONNECTION_POLICY_NEXT_HOP_INTERFACE << ',';
    std::cout << "\"Uint64\":" << FWP_UINT64 << ',' << "\"ByteBlob\":" << FWP_BYTE_BLOB_TYPE << ',' << "\"Sid\":" << FWP_SID << ',';
    std::cout << "\"MatchEqual\":" << FWP_MATCH_EQUAL << ',' << "\"NetworkConnectionPolicyContext\":" << FWPM_NETWORK_CONNECTION_POLICY_CONTEXT << ',';
    std::cout << "\"AleAppId\":\""; print_guid(FWPM_CONDITION_ALE_APP_ID); std::cout << "\",\"AlePackageId\":\""; print_guid(FWPM_CONDITION_ALE_PACKAGE_ID); std::cout << "\"}}";
    return 0;
}
