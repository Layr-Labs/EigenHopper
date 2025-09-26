// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Vm.sol";
import "test/utils/DayTimeLib.sol";

library TimeUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Format: Thu Jan 01 1970 00:00:00 GMT+0000
    function assertEq(uint256 timestamp, string memory dayTimeString) internal pure {
        vm.assertEq(toDayTimeString(timestamp), dayTimeString);
    }

    /// @dev Format: Mon, Tue, Wed, Thu, Fri, Sat, Sun
    function assertWeekdayEq(uint256 timestamp, string memory weekday) internal pure {
        vm.assertEq(weekdayString(timestamp), weekday);
    }

    /// @dev Format: Thu Jan 01 1970 00:00:00 GMT+0000
    /// The same format used by https://www.unixtimestamp.com/.
    function toDayTimeString(uint256 timestamp) internal pure returns (string memory) {
        (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second) =
            DateTimeLib.timestampToDateTime(timestamp);

        return string.concat(
            weekdayString(timestamp),
            " ",
            monthString(month),
            " ",
            toPaddedString(day),
            " ",
            vm.toString(year),
            " ",
            toPaddedString(hour),
            ":",
            toPaddedString(minute),
            ":",
            toPaddedString(second),
            " GMT+0000"
        );
    }

    function weekdayString(uint256 timestamp) internal pure returns (string memory) {
        uint256 weekday = DateTimeLib.weekday(timestamp);
        require(weekday >= 1 && weekday <= 7, "Invalid weekday");
        unchecked {
            return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][weekday - 1]; // checked above
        }
    }

    function monthString(uint256 month) internal pure returns (string memory) {
        require(month >= 1 && month <= 12, "Invalid month");
        unchecked {
            return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1]; // checked above
        }
    }

    function toPaddedString(uint256 value) internal pure returns (string memory) {
        if (value < 10) return string.concat("0", vm.toString(value));
        return vm.toString(value);
    }
}
