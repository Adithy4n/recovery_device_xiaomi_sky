/*
 * Copyright (C) 2026 The OrangeFox Recovery Project
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include <android-base/properties.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <fstream>
#include <glob.h>
#include <string>
#include <thread>
#include <utility>
#include <vector>

/*
 * ---------------------------------------------------------------------------
 * Tunable limits. Change AERA_THERMAL_CPU_MAX_C to move the whole ladder, or
 * override any single value (also from Android.bp with cflags: ["-D...=.."]).
 * All temperatures are in degrees Celsius.
 *
 * With the default CPU max of 80 C the guard behaves like this:
 *   warm      >= 78 C  (2 samples)  -> CPU max frequency capped to 80 %
 *   elevated  >= 83 C               -> 70 %
 *   hot       >= 90 C               -> 55 %
 *   critical  >= 97 C               -> 35 %
 * A state is released after 10 samples below its release temperature.
 * ---------------------------------------------------------------------------
 */
#ifndef AERA_THERMAL_CPU_MAX_C
#define AERA_THERMAL_CPU_MAX_C 80
#endif

#ifndef AERA_THERMAL_WARM_ENTER_C
#define AERA_THERMAL_WARM_ENTER_C (AERA_THERMAL_CPU_MAX_C - 2)
#endif
#ifndef AERA_THERMAL_WARM_RELEASE_C
#define AERA_THERMAL_WARM_RELEASE_C (AERA_THERMAL_CPU_MAX_C - 8)
#endif
#ifndef AERA_THERMAL_ELEVATED_ENTER_C
#define AERA_THERMAL_ELEVATED_ENTER_C (AERA_THERMAL_CPU_MAX_C + 3)
#endif
#ifndef AERA_THERMAL_ELEVATED_RELEASE_C
#define AERA_THERMAL_ELEVATED_RELEASE_C (AERA_THERMAL_CPU_MAX_C - 3)
#endif
#ifndef AERA_THERMAL_HOT_ENTER_C
#define AERA_THERMAL_HOT_ENTER_C (AERA_THERMAL_CPU_MAX_C + 10)
#endif
#ifndef AERA_THERMAL_HOT_RELEASE_C
#define AERA_THERMAL_HOT_RELEASE_C (AERA_THERMAL_CPU_MAX_C + 4)
#endif
#ifndef AERA_THERMAL_CRITICAL_ENTER_C
#define AERA_THERMAL_CRITICAL_ENTER_C (AERA_THERMAL_CPU_MAX_C + 17)
#endif
#ifndef AERA_THERMAL_CRITICAL_RELEASE_C
#define AERA_THERMAL_CRITICAL_RELEASE_C (AERA_THERMAL_CPU_MAX_C + 10)
#endif

// CPU max-frequency cap per state, in percent of the hardware maximum.
#ifndef AERA_THERMAL_CAP_WARM_PCT
#define AERA_THERMAL_CAP_WARM_PCT 80
#endif
#ifndef AERA_THERMAL_CAP_ELEVATED_PCT
#define AERA_THERMAL_CAP_ELEVATED_PCT 70
#endif
#ifndef AERA_THERMAL_CAP_HOT_PCT
#define AERA_THERMAL_CAP_HOT_PCT 55
#endif
#ifndef AERA_THERMAL_CAP_CRITICAL_PCT
#define AERA_THERMAL_CAP_CRITICAL_PCT 35
#endif

#ifndef AERA_THERMAL_POLL_SECONDS
#define AERA_THERMAL_POLL_SECONDS 3
#endif

// Thermal zones whose "type" starts with one of these are monitored (the
// hottest one wins). "cpu-hw-trip-*" zones are always skipped.
#ifndef AERA_THERMAL_SENSOR_PREFIXES
#define AERA_THERMAL_SENSOR_PREFIXES "cpu-", "cpuss-", "cpullc-", "qmx-"
#endif

// Used when no zone matches the prefixes above. This is the same zone as
// AERA_CUSTOM_CPU_TEMP_PATH in BoardConfig.mk.
#ifndef AERA_THERMAL_FALLBACK_TEMP_PATH
#define AERA_THERMAL_FALLBACK_TEMP_PATH "/sys/class/thermal/thermal_zone34/temp"
#endif

namespace {

constexpr auto kPollInterval = std::chrono::seconds(AERA_THERMAL_POLL_SECONDS);
constexpr int kWarmSamples = 2;
constexpr int kReleaseSamples = 10;  // 30 seconds at the default 3 s poll interval.
constexpr int kReapplySamples = 10;

// Millidegrees Celsius, derived from the #defines at the top of this file.
constexpr int64_t kWarmEnter = AERA_THERMAL_WARM_ENTER_C * 1000;
constexpr int64_t kWarmRelease = AERA_THERMAL_WARM_RELEASE_C * 1000;
constexpr int64_t kElevatedEnter = AERA_THERMAL_ELEVATED_ENTER_C * 1000;
constexpr int64_t kElevatedRelease = AERA_THERMAL_ELEVATED_RELEASE_C * 1000;
constexpr int64_t kHotEnter = AERA_THERMAL_HOT_ENTER_C * 1000;
constexpr int64_t kHotRelease = AERA_THERMAL_HOT_RELEASE_C * 1000;
constexpr int64_t kCriticalEnter = AERA_THERMAL_CRITICAL_ENTER_C * 1000;
constexpr int64_t kCriticalRelease = AERA_THERMAL_CRITICAL_RELEASE_C * 1000;

static_assert(kWarmEnter < kElevatedEnter && kElevatedEnter < kHotEnter && kHotEnter < kCriticalEnter,
              "thermal enter temperatures must increase: warm < elevated < hot < critical");
static_assert(kWarmRelease < kWarmEnter && kElevatedRelease < kElevatedEnter &&
                  kHotRelease < kHotEnter && kCriticalRelease < kCriticalEnter,
              "each release temperature must be below its enter temperature");

const char* const kSensorPrefixes[] = {AERA_THERMAL_SENSOR_PREFIXES};

enum class State { kNormal, kWarm, kElevated, kHot, kCritical };

struct CpuPolicy {
    std::string path;
    int64_t hardware_max = 0;
    int64_t original_max = 0;
    int64_t last_written = 0;
    std::vector<int64_t> available_frequencies;
};

struct ThermalSensor {
    std::string path;
    std::string name;
};

struct ThermalReading {
    int64_t temperature = 0;
    std::string sensor;
};

std::atomic_bool g_running{true};

void HandleSignal(int) {
    g_running = false;
}

void Log(const std::string& message) {
    std::ofstream kmsg("/dev/kmsg");
    if (kmsg)
        kmsg << "[aera-thermal-guard] " << message << '\n';
}

bool ReadInt(const std::string& path, int64_t* value) {
    std::ifstream input(path);
    return input && (input >> *value);
}

std::string ReadString(const std::string& path) {
    std::ifstream input(path);
    std::string value;
    input >> value;
    return value;
}

bool WriteInt(const std::string& path, int64_t value) {
    std::ofstream output(path);
    if (!output)
        return false;
    output << value;
    return output.good();
}

bool StartsWith(const std::string& value, const std::string& prefix) {
    return value.compare(0, prefix.size(), prefix) == 0;
}

std::vector<int64_t> ReadFrequencies(const std::string& path) {
    std::vector<int64_t> frequencies;
    std::ifstream input(path);
    int64_t frequency;
    while (input >> frequency) {
        if (frequency > 0)
            frequencies.push_back(frequency);
    }
    std::sort(frequencies.begin(), frequencies.end());
    frequencies.erase(std::unique(frequencies.begin(), frequencies.end()), frequencies.end());
    return frequencies;
}

std::vector<CpuPolicy> DiscoverPolicies() {
    std::vector<CpuPolicy> policies;
    glob_t matches{};
    if (glob("/sys/devices/system/cpu/cpufreq/policy*", 0, nullptr, &matches) != 0)
        return policies;

    for (size_t i = 0; i < matches.gl_pathc; ++i) {
        CpuPolicy policy;
        policy.path = matches.gl_pathv[i];
        if (!ReadInt(policy.path + "/cpuinfo_max_freq", &policy.hardware_max) ||
            !ReadInt(policy.path + "/scaling_max_freq", &policy.original_max) ||
            policy.hardware_max <= 0 || policy.original_max <= 0) {
            continue;
        }
        policy.available_frequencies =
            ReadFrequencies(policy.path + "/scaling_available_frequencies");
        policies.push_back(std::move(policy));
    }
    globfree(&matches);
    return policies;
}

std::vector<ThermalSensor> DiscoverSensors() {
    std::vector<ThermalSensor> sensors;
    glob_t matches{};
    if (glob("/sys/class/thermal/thermal_zone*", 0, nullptr, &matches) == 0) {
        for (size_t i = 0; i < matches.gl_pathc; ++i) {
            const std::string zone = matches.gl_pathv[i];
            const std::string name = ReadString(zone + "/type");
            if (name.empty() || StartsWith(name, "cpu-hw-trip-"))
                continue;
            for (const char* prefix : kSensorPrefixes) {
                if (StartsWith(name, prefix)) {
                    sensors.push_back({zone + "/temp", name});
                    break;
                }
            }
        }
        globfree(&matches);
    }

    int64_t probe;
    if (sensors.empty() && ReadInt(AERA_THERMAL_FALLBACK_TEMP_PATH, &probe)) {
        Log("no zone matched the sensor prefixes; using " AERA_THERMAL_FALLBACK_TEMP_PATH);
        sensors.push_back({AERA_THERMAL_FALLBACK_TEMP_PATH, "fallback-zone"});
    }
    return sensors;
}

ThermalReading ReadHottest(const std::vector<ThermalSensor>& sensors) {
    ThermalReading hottest;
    for (const auto& sensor : sensors) {
        int64_t temperature;
        if (!ReadInt(sensor.path, &temperature))
            continue;
        if (temperature > 0 && temperature < 1000)
            temperature *= 1000;
        if (temperature <= 0 || temperature >= 200000)
            continue;
        if (temperature > hottest.temperature)
            hottest = {temperature, sensor.name};
    }
    return hottest;
}

int CapPercent(State state) {
    switch (state) {
        case State::kWarm: return AERA_THERMAL_CAP_WARM_PCT;
        case State::kElevated: return AERA_THERMAL_CAP_ELEVATED_PCT;
        case State::kHot: return AERA_THERMAL_CAP_HOT_PCT;
        case State::kCritical: return AERA_THERMAL_CAP_CRITICAL_PCT;
        case State::kNormal: return 100;
    }
}

const char* StateName(State state) {
    switch (state) {
        case State::kWarm: return "warm";
        case State::kElevated: return "elevated";
        case State::kHot: return "hot";
        case State::kCritical: return "critical";
        case State::kNormal: return "normal";
    }
}

int64_t ChooseCap(const CpuPolicy& policy, int percent) {
    if (percent == 100)
        return policy.original_max;

    const int64_t target = policy.hardware_max * percent / 100;
    int64_t selected = 0;
    for (int64_t frequency : policy.available_frequencies) {
        if (frequency <= target)
            selected = frequency;
        else
            break;
    }
    return selected > 0 ? selected : target;
}

void ApplyState(std::vector<CpuPolicy>* policies, State state,
                const ThermalReading& reading) {
    const int percent = CapPercent(state);
    for (auto& policy : *policies) {
        int64_t current;
        if (!ReadInt(policy.path + "/scaling_max_freq", &current))
            continue;

        const int64_t target = ChooseCap(policy, percent);
        bool should_write = false;
        if (state == State::kNormal) {
            // Raise a limit only when it still equals the value this daemon
            // wrote. A different lower value belongs to another controller.
            should_write = policy.last_written > 0 && current == policy.last_written;
        } else if (current > target) {
            should_write = true;
        } else if (policy.last_written > 0 && current == policy.last_written &&
                   target > current) {
            // Controlled step-down from a stronger guard state.
            should_write = true;
        }

        if (should_write) {
            if (WriteInt(policy.path + "/scaling_max_freq", target))
                policy.last_written = target;
            else
                Log("failed to write " + policy.path + ": " + std::to_string(errno));
        } else if (current != policy.last_written) {
            policy.last_written = 0;
        }

        if (state == State::kNormal)
            policy.last_written = 0;
    }

    android::base::SetProperty("aera.thermal.status", StateName(state));
    android::base::SetProperty("aera.thermal.temp", std::to_string(reading.temperature));
    android::base::SetProperty("aera.thermal.sensor", reading.sensor);
    android::base::SetProperty("aera.thermal.cap_pct", std::to_string(percent));
    Log(std::string("state=") + StateName(state) + " sensor=" + reading.sensor +
        " temp=" + std::to_string(reading.temperature / 1000) + "C cpu_cap=" +
        std::to_string(percent) + "%");
}

void Restore(std::vector<CpuPolicy>* policies) {
    for (auto& policy : *policies) {
        int64_t current;
        if (policy.last_written > 0 &&
            ReadInt(policy.path + "/scaling_max_freq", &current) &&
            current == policy.last_written) {
            WriteInt(policy.path + "/scaling_max_freq", policy.original_max);
        }
        policy.last_written = 0;
    }
    android::base::SetProperty("aera.thermal.status", "stopped");
    android::base::SetProperty("aera.thermal.cap_pct", "100");
    Log("restored daemon-owned CPU limits");
}

State UpdateState(State state, int64_t temperature, int* warm_samples,
                  int* release_samples) {
    if (temperature >= kCriticalEnter) {
        *warm_samples = 0;
        *release_samples = 0;
        return State::kCritical;
    }
    if (state != State::kCritical && temperature >= kHotEnter) {
        *warm_samples = 0;
        *release_samples = 0;
        return State::kHot;
    }
    if ((state == State::kNormal || state == State::kWarm) &&
        temperature >= kElevatedEnter) {
        *warm_samples = 0;
        *release_samples = 0;
        return State::kElevated;
    }

    int64_t release_threshold = 0;
    State released_state = state;
    switch (state) {
        case State::kCritical:
            release_threshold = kCriticalRelease;
            released_state = State::kHot;
            break;
        case State::kHot:
            release_threshold = kHotRelease;
            released_state = State::kElevated;
            break;
        case State::kElevated:
            release_threshold = kElevatedRelease;
            released_state = State::kWarm;
            break;
        case State::kWarm:
            release_threshold = kWarmRelease;
            released_state = State::kNormal;
            break;
        case State::kNormal:
            if (temperature >= kWarmEnter) {
                ++*warm_samples;
                if (*warm_samples >= kWarmSamples) {
                    *warm_samples = 0;
                    return State::kWarm;
                }
            } else {
                *warm_samples = 0;
            }
            return State::kNormal;
    }

    if (temperature < release_threshold) {
        ++*release_samples;
        if (*release_samples >= kReleaseSamples) {
            *release_samples = 0;
            return released_state;
        }
    } else {
        *release_samples = 0;
    }
    return state;
}

}  // namespace

int main() {
    std::signal(SIGINT, HandleSignal);
    std::signal(SIGTERM, HandleSignal);

    auto policies = DiscoverPolicies();
    const auto sensors = DiscoverSensors();
    if (policies.empty() || sensors.empty()) {
        Log("missing usable CPU policies or thermal sensors");
        return 1;
    }

    State state = State::kNormal;
    int warm_samples = 0;
    int release_samples = 0;
    int reapply_samples = 0;
    int64_t peak_temperature = 0;
    std::string peak_sensor;

    android::base::SetProperty("aera.thermal.status", "normal");
    android::base::SetProperty("aera.thermal.cap_pct", "100");
    Log("started with " + std::to_string(policies.size()) + " CPU policies and " +
        std::to_string(sensors.size()) + " thermal sensors");

    while (g_running) {
        const ThermalReading reading = ReadHottest(sensors);
        if (reading.temperature <= 0) {
            Log("all monitored sensors unavailable; stopping fail-open");
            break;
        }

        android::base::SetProperty("aera.thermal.temp", std::to_string(reading.temperature));
        android::base::SetProperty("aera.thermal.sensor", reading.sensor);
        if (reading.temperature > peak_temperature) {
            peak_temperature = reading.temperature;
            peak_sensor = reading.sensor;
            android::base::SetProperty("aera.thermal.peak_temp",
                                       std::to_string(peak_temperature));
            android::base::SetProperty("aera.thermal.peak_sensor", peak_sensor);
        }

        const State next = UpdateState(state, reading.temperature, &warm_samples,
                                       &release_samples);
        ++reapply_samples;
        if (next != state || (state != State::kNormal &&
                              reapply_samples >= kReapplySamples)) {
            state = next;
            ApplyState(&policies, state, reading);
            reapply_samples = 0;
        }

        for (int i = 0; i < kPollInterval.count() && g_running; ++i)
            std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    Restore(&policies);
    return 0;
}
