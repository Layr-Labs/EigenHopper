// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Vm.sol";
import "test/utils/DayTimeLib.sol";

library TimeUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 timestamp, string memory dayTimeString) internal {
        vm.assertEq(toDayTimeString(timestamp), dayTimeString);
    }

    /// @dev Format: Thu Aug 15 2024 00:00:00 GMT+0000
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
        if (weekday == 1) return "Mon";
        if (weekday == 2) return "Tue";
        if (weekday == 3) return "Wed";
        if (weekday == 4) return "Thu";
        if (weekday == 5) return "Fri";
        if (weekday == 6) return "Sat";
        if (weekday == 7) return "Sun";
        revert("Invalid weekday");
    }

    function monthString(uint256 month) internal pure returns (string memory) {
        if (month == 1) return "Jan";
        if (month == 2) return "Feb";
        if (month == 3) return "Mar";
        if (month == 4) return "Apr";
        if (month == 5) return "May";
        if (month == 6) return "Jun";
        if (month == 7) return "Jul";
        if (month == 8) return "Aug";
        if (month == 9) return "Sep";
        if (month == 10) return "Oct";
        if (month == 11) return "Nov";
        if (month == 12) return "Dec";
        revert("Invalid month");
    }

    function toPaddedString(uint256 value) internal pure returns (string memory) {
        if (value < 10) return string.concat("0", vm.toString(value));
        return vm.toString(value);
    }
}
